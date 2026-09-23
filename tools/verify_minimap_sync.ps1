[CmdletBinding()]
param(
    [string]$GameRoot = '',
    [string]$ContentRoot = '',
    [string]$ResourceCompiler = '',
    [ValidateSet('template_map')][string]$MapName = 'template_map',
    [ValidateRange(0, 8192)][int]$ExpectedOutputSize = 0,
    [double]$ExpectedPosX = -16384,
    [double]$ExpectedPosY = 16384,
    [double]$ExpectedScale = 32,
    [switch]$CheckCompilerDependencies,
    [switch]$RequireCleanGit,
    [switch]$SourceOnly,
    [switch]$AsObject,
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
function Check($condition, [string]$message) { if (-not $condition) { throw $message } }
function Resolve-AddonRoot([string]$candidate) {
    if ($candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    $cursor = $PSScriptRoot
    while ($cursor) {
        if (Test-Path -LiteralPath (Join-Path $cursor 'resource/overviews/template_map.txt')) { return $cursor }
        $cursor = Split-Path -Parent $cursor
    }
    throw 'MINIMAP_GAME_ROOT_REQUIRED'
}
function Resource-Path([string]$root, [string]$relative) {
    Check ($relative -match '^materials/[A-Za-z0-9_./-]+$' -and $relative -notmatch '(^|/)\.\.?(/|$)') 'MINIMAP_UNSAFE_RESOURCE_PATH'
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    Check ($full.StartsWith($root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'MINIMAP_RESOURCE_OUTSIDE_ADDON'
    return $full
}
function Required([string]$file) {
    Check (Test-Path -LiteralPath $file -PathType Leaf) "MINIMAP_FILE_MISSING: $file"
    Check ((Get-Item -LiteralPath $file).Length -gt 0) "MINIMAP_FILE_EMPTY: $file"
    return $file
}
function KV-Value([string]$body, [string]$key) {
    # Accept native generated unquoted overview values and quoted VMAT values.
    $pattern = '(?m)^\s*"?' + [regex]::Escape($key) + '"?\s+(?:"([^"\r\n]+)"|([^\s{}]+))\s*(?://[^\r\n]*)?$'
    $found = [regex]::Matches($body, $pattern)
    Check ($found.Count -eq 1) "MINIMAP_KEY_MISSING_OR_AMBIGUOUS: $key"
    if ($found[0].Groups[1].Success) { return $found[0].Groups[1].Value }
    return $found[0].Groups[2].Value
}
function Number-Value([string]$body, [string]$key) {
    $value = [double]::Parse((KV-Value $body $key), [Globalization.CultureInfo]::InvariantCulture)
    Check (-not [double]::IsNaN($value) -and -not [double]::IsInfinity($value)) "MINIMAP_INVALID_NUMBER: $key"
    return $value
}
function File-Record([string]$path, [string]$root) {
    $file = Get-Item -LiteralPath $path
    return [ordered]@{ path = $path.Substring($root.Length + 1).Replace('\', '/'); bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(); modified_utc = $file.LastWriteTimeUtc.ToString('o') }
}

$game = Resolve-AddonRoot $GameRoot
if (-not $ContentRoot) {
    Check ($game -match '[\\/]game[\\/]dota_addons[\\/][^\\/]+$') 'MINIMAP_CONTENT_ROOT_REQUIRED'
    $ContentRoot = $game -replace '([\\/])game([\\/])dota_addons([\\/])', '${1}content${2}dota_addons${3}'
}
$content = (Resolve-Path -LiteralPath $ContentRoot).Path
$overview = Required (Join-Path $game "resource/overviews/$MapName.txt")
$overviewText = [IO.File]::ReadAllText($overview)
$materialRelative = (KV-Value $overviewText 'material').Replace('\', '/')
Check ($materialRelative -match '\.vmat$') 'MINIMAP_OVERVIEW_MUST_REFERENCE_VMAT'
$sourceMaterial = Required (Resource-Path $content $materialRelative)
$materialText = [IO.File]::ReadAllText($sourceMaterial)
Check ((KV-Value $materialText 'Shader') -eq 'ui.vfx') 'MINIMAP_MATERIAL_SHADER_INVALID'
$textureRelative = (KV-Value $materialText 'Texture').Replace('\', '/')
$sourceTexture = Required (Resource-Path $content $textureRelative)
$sourceImage = $sourceTexture
$imageRelative = $textureRelative
$textureDefinition = $null
if ($textureRelative -match '\.vtex$') {
    $textureDefinition = $sourceTexture
    $vtexText = [IO.File]::ReadAllText($textureDefinition)
    $inputs = [regex]::Matches($vtexText, '"m_fileName"\s+"string"\s+"([^"\r\n]+)"')
    Check ($inputs.Count -eq 1) 'MINIMAP_VTEX_REQUIRES_SINGLE_TGA_INPUT'
    $inputName = $inputs[0].Groups[1].Value.Replace('\', '/')
    if ($inputName.StartsWith('materials/')) { $imageRelative = $inputName }
    else {
        Check ($inputName -match '^(\./)?[A-Za-z0-9_-]+\.tga$') 'MINIMAP_UNSAFE_VTEX_INPUT'
        $imageRelative = $textureRelative.Substring(0, $textureRelative.LastIndexOf('/') + 1) + ($inputName -replace '^\./', '')
    }
    $sourceImage = Required (Resource-Path $content $imageRelative)
}
Check ($imageRelative -match '\.tga$') 'MINIMAP_TEXTURE_FORMAT_NOT_SUPPORTED: expected TGA or single-input VTEX'
$settings = [IO.Path]::ChangeExtension($sourceImage, '.txt')
if (-not $textureDefinition) {
    $null = Required $settings
    $settingsText = [IO.File]::ReadAllText($settings)
    foreach ($key in @('clampu', 'clampv', 'nocompress', 'nomip')) {
        Check ((KV-Value $settingsText $key) -eq '1') "MINIMAP_TEXTURE_SETTING_REQUIRED: $key=1"
    }
}

$posX = Number-Value $overviewText 'pos_x'
$posY = Number-Value $overviewText 'pos_y'
$scale = Number-Value $overviewText 'scale'
Check ($scale -gt 0 -and [Math]::Abs($posX - $ExpectedPosX) -lt 0.001 -and [Math]::Abs($posY - $ExpectedPosY) -lt 0.001 -and [Math]::Abs($scale - $ExpectedScale) -lt 0.000001) 'MINIMAP_OVERVIEW_BOUNDS_MISMATCH'
# Dota's current overview contract uses a 1024-unit reference, independent of
# output raster resolution. Do not divide world extent by the TGA width.
$bounds = [ordered]@{ pos_x = $posX; pos_y = $posY; scale = $scale; reference_pixels = 1024; min_x = $posX; max_x = $posX + 1024 * $scale; min_y = $posY - 1024 * $scale; max_y = $posY }
$bytes = [IO.File]::ReadAllBytes($sourceImage)
Check ($bytes.Length -ge 18) 'MINIMAP_TGA_HEADER_MISSING'
Check ($bytes[1] -eq 0 -and $bytes[2] -eq 2) 'MINIMAP_TGA_MUST_BE_UNCOMPRESSED_TRUE_COLOR'
$width = [int][BitConverter]::ToUInt16($bytes, 12)
$height = [int][BitConverter]::ToUInt16($bytes, 14)
$bpp = [int]$bytes[16]
Check ($width -ge 256 -and $width -le 8192 -and $width -eq $height -and ($width -band ($width - 1)) -eq 0) "MINIMAP_TGA_DIMENSIONS_INVALID: ${width}x${height}"
Check ($bpp -eq 24 -or $bpp -eq 32) 'MINIMAP_TGA_BPP_INVALID'
Check ($bytes.Length -ge (18 + $bytes[0] + [long]$width * $height * ($bpp / 8))) 'MINIMAP_TGA_PIXEL_DATA_TRUNCATED'
if ($ExpectedOutputSize) { Check ($width -eq $ExpectedOutputSize) 'MINIMAP_TGA_OUTPUT_SIZE_MISMATCH' }
$bytes = $null

$mapSource = Required (Join-Path $content "maps/$MapName.vmap")
$mapPackage = Required (Join-Path $game "maps/$MapName.vpk")
$compiledMaterial = Resource-Path $game ($materialRelative + '_c')
$compiledTexture = $null
$compiledRelative = $null
$dependencyChecked = $false
if (-not $SourceOnly) {
    $null = Required $compiledMaterial
    $compiledText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($compiledMaterial))
    $references = @([regex]::Matches($compiledText.Replace('\', '/'), 'materials/[A-Za-z0-9_./-]+\.vtex(?:_c)?') | ForEach-Object { $_.Value -replace '_c$', '' } | Select-Object -Unique)
    if ($textureDefinition) { $expectedReference = '^' + [regex]::Escape($textureRelative) + '$' }
    else { $expectedReference = '^' + [regex]::Escape(($imageRelative -replace '\.tga$', '')) + '_tga_[0-9a-fA-F]+\.vtex$' }
    $matching = @($references | Where-Object { $_ -match $expectedReference })
    Check ($matching.Count -eq 1) 'MINIMAP_COMPILED_TEXTURE_REFERENCE_MISSING_OR_AMBIGUOUS'
    $compiledRelative = $matching[0] + '_c'
    $compiledTexture = Required (Resource-Path $game $compiledRelative)
    $compiledTextureText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($compiledTexture)).Replace('\', '/')
    Check ($compiledTextureText.IndexOf($imageRelative, [StringComparison]::OrdinalIgnoreCase) -ge 0) 'MINIMAP_COMPILED_TEXTURE_SOURCE_REFERENCE_MISSING'
    Check ((Get-Item -LiteralPath $sourceImage).LastWriteTimeUtc -ge (Get-Item -LiteralPath $mapPackage).LastWriteTimeUtc) 'MINIMAP_IMAGE_OLDER_THAN_MAP: regenerate on the newly compiled map'
    Check ((Get-Item -LiteralPath $compiledMaterial).LastWriteTimeUtc -ge (Get-Item -LiteralPath $sourceMaterial).LastWriteTimeUtc) 'MINIMAP_COMPILED_MATERIAL_OLDER_THAN_SOURCE'
    Check ((Get-Item -LiteralPath $compiledTexture).LastWriteTimeUtc -ge (Get-Item -LiteralPath $sourceImage).LastWriteTimeUtc) 'MINIMAP_COMPILED_TEXTURE_OLDER_THAN_SOURCE'
    if ($textureDefinition) { Check ((Get-Item -LiteralPath $compiledTexture).LastWriteTimeUtc -ge (Get-Item -LiteralPath $textureDefinition).LastWriteTimeUtc) 'MINIMAP_COMPILED_TEXTURE_OLDER_THAN_DEFINITION' }
    if ($CheckCompilerDependencies) {
        if (-not $ResourceCompiler) { $ResourceCompiler = Join-Path ([IO.Path]::GetFullPath((Join-Path $game '../../..'))) 'game/bin/win64/resourcecompiler.exe' }
        $null = Required $ResourceCompiler
        # This mode checks dependency CRCs; it must never compile missing outputs.
        $dependencyOutput = @(& $ResourceCompiler -dependency_check_only -v $sourceMaterial 2>&1)
        $dependencyExit = $LASTEXITCODE
        $dependencyText = ($dependencyOutput | ForEach-Object { $_.ToString() }) -join "`n"
        Check ($dependencyExit -eq 0 -and $dependencyText -notmatch 'Existing file invalid|Special-dep mismatch' -and $dependencyText -match 'OK:\s+0 compiled, 0 failed, [1-9][0-9]* skipped') 'MINIMAP_COMPILER_DEPENDENCY_CHECK_FAILED'
        $dependencyChecked = $true
    }
}

$sourcePaths = @($sourceMaterial, $sourceImage, $mapSource)
if ($textureDefinition) { $sourcePaths += $textureDefinition }
if (Test-Path -LiteralPath $settings -PathType Leaf) { $sourcePaths += $settings }
$gamePaths = @($overview, $mapPackage)
if (-not $SourceOnly) { $gamePaths += @($compiledMaterial, $compiledTexture) }
if ($RequireCleanGit) {
    foreach ($item in @(@{root = $game; paths = $gamePaths}, @{root = $content; paths = $sourcePaths})) {
        $relativePaths = @($item.paths | ForEach-Object { $_.Substring($item.root.Length + 1).Replace('\', '/') })
        $status = @(& git -C $item.root status --porcelain -- @relativePaths 2>&1)
        Check ($LASTEXITCODE -eq 0 -and $status.Count -eq 0) 'MINIMAP_RELEVANT_FILES_NOT_CLEAN'
    }
}
$report = [pscustomobject][ordered]@{
    schema = 1; status = $(if ($SourceOnly) { 'source_validated_only' } else { 'resource_chain_pass' }); map = $MapName
    game_root = $game; content_root = $content; material = $materialRelative; texture = $textureRelative
    source_image = $imageRelative; compiled_texture = $compiledRelative; settings = $(if (Test-Path -LiteralPath $settings) { $settings.Substring($content.Length + 1).Replace('\', '/') } else { $null })
    tga = [ordered]@{ width = $width; height = $height; bits_per_pixel = $bpp }; bounds = $bounds
    compiler_dependencies_checked = $dependencyChecked; visual_current_map_verified = $false; navigation_verified = $false
    source_files = @($sourcePaths | Select-Object -Unique | ForEach-Object { File-Record $_ $content })
    game_files = @($gamePaths | Select-Object -Unique | ForEach-Object { File-Record $_ $game })
}
if ($ReportPath) {
    Check (-not (Test-Path -LiteralPath $ReportPath)) 'MINIMAP_REPORT_ALREADY_EXISTS'
    $reportFullPath = [IO.Path]::GetFullPath($ReportPath)
    Check (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($reportFullPath)) -PathType Container) 'MINIMAP_REPORT_PARENT_MISSING'
    $stream = [IO.File]::Open($reportFullPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $data = [Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Depth 8)); $stream.Write($data, 0, $data.Length) } finally { $stream.Dispose() }
}
if ($AsObject) { return $report }
Write-Host $(if ($SourceOnly) { 'MINIMAP_SOURCE_CHECK_PASS' } else { 'MINIMAP_SYNC_PASS' })
Write-Host ($report | ConvertTo-Json -Depth 8)
