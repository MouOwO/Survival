param(
    [string]$GameRoot = "",
    [string]$ContentRoot = "",
    [string]$ResourceCompiler = "",
    [switch]$RequireCleanGit
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($ContentRoot)) {
    $ContentRoot = $GameRoot -replace '\\game\\dota_addons\\Survival$', '\content\dota_addons\Survival'
}

function Check($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Resolve-RequiredFile([string]$root, [string]$relativePath) {
    $path = Join-Path $root $relativePath
    Check (Test-Path -LiteralPath $path -PathType Leaf) "MINIMAP_FILE_MISSING: $path"
    return (Resolve-Path -LiteralPath $path).Path
}

function Get-Sha256([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

function Invoke-Git([string]$root, [string[]]$arguments) {
    $output = @(& git -C $root @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | ForEach-Object { $_.ToString() }) -join " | "
        throw "GIT_COMMAND_FAILED: git -C $root $($arguments -join ' '): $detail"
    }
    return $output
}

$game = (Resolve-Path -LiteralPath $GameRoot).Path
$content = (Resolve-Path -LiteralPath $ContentRoot).Path

$overview = Resolve-RequiredFile $game "resource\overviews\template_map.txt"
$sourceImage = Resolve-RequiredFile $content "materials\overviews\survival_minimap.tga"
$sourceMaterial = Resolve-RequiredFile $content "materials\overviews\survival_minimap.vmat"
$sourceSettings = Resolve-RequiredFile $content "materials\overviews\survival_minimap.txt"
$compiledMaterial = Resolve-RequiredFile $game "materials\overviews\survival_minimap.vmat_c"
$compiledTexture = Resolve-RequiredFile $game "materials\overviews\survival_minimap_tga_81334029.vtex_c"
$mapPackage = Resolve-RequiredFile $game "maps\template_map.vpk"

if ($RequireCleanGit) {
    $gamePaths = @(
        "resource/overviews/template_map.txt",
        "materials/overviews/survival_minimap.vmat_c",
        "materials/overviews/survival_minimap_tga_81334029.vtex_c",
        "maps/template_map.vpk"
    )
    $contentPaths = @(
        "materials/overviews/survival_minimap.tga",
        "materials/overviews/survival_minimap.vmat",
        "materials/overviews/survival_minimap.txt"
    )
    $gameStatus = @(Invoke-Git $game (@("status", "--porcelain", "--") + $gamePaths))
    $contentStatus = @(Invoke-Git $content (@("status", "--porcelain", "--") + $contentPaths))
    Check ($gameStatus.Count -eq 0) `
        "MINIMAP_GAME_GIT_DIRTY: $($gameStatus -join '; ')"
    Check ($contentStatus.Count -eq 0) `
        "MINIMAP_CONTENT_GIT_DIRTY: $($contentStatus -join '; ')"
}

$overviewText = [IO.File]::ReadAllText($overview)
$materialText = [IO.File]::ReadAllText($sourceMaterial)
$settingsText = [IO.File]::ReadAllText($sourceSettings)

Check ($overviewText -match '(?m)^\s*material\s+materials/overviews/survival_minimap\.vmat\s*$') `
    "MINIMAP_OVERVIEW_MATERIAL_REFERENCE_INVALID"
Check ($overviewText -match '(?m)^\s*pos_x\s+-8192\s*$') `
    "MINIMAP_OVERVIEW_POS_X_INVALID"
Check ($overviewText -match '(?m)^\s*pos_y\s+8192\s*$') `
    "MINIMAP_OVERVIEW_POS_Y_INVALID"
Check ($overviewText -match '(?m)^\s*scale\s+16\.000\s*$') `
    "MINIMAP_OVERVIEW_SCALE_INVALID"
Check ($materialText -match '"Shader"\s+"ui\.vfx"') `
    "MINIMAP_MATERIAL_SHADER_INVALID"
Check ($materialText -match '"Texture"\s+"materials/overviews/survival_minimap\.tga"') `
    "MINIMAP_MATERIAL_TEXTURE_REFERENCE_INVALID"
Check ($settingsText -match '"nocompress"\s+"1"') `
    "MINIMAP_SETTINGS_NOCOMPRESS_MISSING"
Check ($settingsText -match '"nomip"\s+"1"') `
    "MINIMAP_SETTINGS_NOMIP_MISSING"

$imageBytes = [IO.File]::ReadAllBytes($sourceImage)
Check ($imageBytes.Length -ge 18) "MINIMAP_TGA_HEADER_MISSING"
Check ($imageBytes[2] -eq 2) "MINIMAP_TGA_MUST_BE_UNCOMPRESSED_TRUE_COLOR"
$width = [BitConverter]::ToUInt16($imageBytes, 12)
$height = [BitConverter]::ToUInt16($imageBytes, 14)
$bitsPerPixel = $imageBytes[16]
Check ($width -eq 512 -and $height -eq 512) "MINIMAP_TGA_DIMENSIONS_INVALID: ${width}x${height}"
Check ($bitsPerPixel -eq 24) "MINIMAP_TGA_BPP_INVALID: $bitsPerPixel"

$compiledMaterialBytes = [IO.File]::ReadAllBytes($compiledMaterial)
$compiledTextureBytes = [IO.File]::ReadAllBytes($compiledTexture)
Check ($compiledMaterialBytes.Length -gt 0) "MINIMAP_COMPILED_MATERIAL_EMPTY"
Check ($compiledTextureBytes.Length -gt 0) "MINIMAP_COMPILED_TEXTURE_EMPTY"
$compiledMaterialText = [Text.Encoding]::ASCII.GetString($compiledMaterialBytes)
$compiledTextureText = [Text.Encoding]::ASCII.GetString($compiledTextureBytes)
Check ($compiledMaterialText.Contains("survival_minimap_tga_81334029.vtex")) `
    "MINIMAP_COMPILED_MATERIAL_TEXTURE_REFERENCE_MISSING"
Check ($compiledTextureText.Contains("materials/overviews/survival_minimap.tga")) `
    "MINIMAP_COMPILED_TEXTURE_SOURCE_REFERENCE_MISSING"

if ([string]::IsNullOrWhiteSpace($ResourceCompiler)) {
    $dotaRoot = $game -replace '\\game\\dota_addons\\Survival$', ''
    $ResourceCompiler = Join-Path $dotaRoot "game\bin\win64\resourcecompiler.exe"
}
Check (Test-Path -LiteralPath $ResourceCompiler -PathType Leaf) `
    "RESOURCECOMPILER_NOT_FOUND: $ResourceCompiler"

$dependencyOutput = @(& $ResourceCompiler -dependency_check_only -v $sourceMaterial 2>&1)
$dependencyExit = $LASTEXITCODE
$dependencyText = ($dependencyOutput | ForEach-Object { $_.ToString() }) -join "`n"
Check ($dependencyExit -eq 0) "MINIMAP_DEPENDENCY_CHECK_FAILED: exit=$dependencyExit"
Check (-not $dependencyText.Contains("Existing file invalid")) `
    "MINIMAP_COMPILED_RESOURCE_INVALID"
Check (-not $dependencyText.Contains("Special-dep mismatch")) `
    "MINIMAP_COMPILED_RESOURCE_DEPENDENCY_MISMATCH"
Check ($dependencyText.Contains("Texture Encode Quality")) `
    "MINIMAP_TEXTURE_ENCODE_QUALITY_DEPENDENCY_MISSING"
Check ($dependencyText -match 'OK:\s+0 compiled, 0 failed, 1 skipped') `
    "MINIMAP_COMPILED_RESOURCE_NOT_UP_TO_DATE"

Write-Host "MINIMAP_SYNC_PASS"
Write-Host "CONTENT_ROOT=$content"
Write-Host "GAME_ROOT=$game"
Write-Host "SOURCE_TGA_SHA256=$(Get-Sha256 $sourceImage)"
Write-Host "COMPILED_VMAT_C_SHA256=$(Get-Sha256 $compiledMaterial)"
Write-Host "COMPILED_VTEX_C_SHA256=$(Get-Sha256 $compiledTexture)"
Write-Host "MAP_VPK_SHA256=$(Get-Sha256 $mapPackage)"
Write-Host "MINIMAP_TGA=${width}x${height}x${bitsPerPixel}"
Write-Host "RESOURCECOMPILER=$ResourceCompiler"