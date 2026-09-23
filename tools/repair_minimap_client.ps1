[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GameRoot = '',
    [string]$ContentRoot = '',
    [string]$ResourceCompiler = '',
    [string]$VerifyScript = '',
    [ValidateRange(1, 65535)][int]$ConsolePort = 29000,
    [ValidateRange(1000, 60000)][int]$ConsoleTimeoutMs = 60000,
    [ValidateSet(512, 1024, 2048, 4096)][int]$OutputSize = 2048,
    [double]$ExpectedPosX = -16384,
    [double]$ExpectedPosY = 16384,
    [double]$ExpectedScale = 32
)

$ErrorActionPreference = 'Stop'
function Check($condition, [string]$message) { if (-not $condition) { throw $message } }
function Find-AddonRoot([string]$candidate) {
    if ($candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    $cursor = $PSScriptRoot
    while ($cursor) {
        if (Test-Path -LiteralPath (Join-Path $cursor 'tools/map_c6/console.cjs')) { return $cursor }
        $cursor = Split-Path -Parent $cursor
    }
    throw 'MINIMAP_GAME_ROOT_REQUIRED'
}
function Invoke-Captured([string]$program, [string[]]$arguments) {
    # console.cjs can receive unrelated live output. Keep it in memory and only
    # expose our exact nonce result, never raw console/cvars/authentication data.
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $lines = @(& $program @arguments 2>&1); $exitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $oldPreference }
    return [pscustomobject]@{ exit_code = $exitCode; text = ($lines | ForEach-Object { $_.ToString() }) -join "`n" }
}
function Write-NewJson([string]$path, $value) {
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $data = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $value -Depth 10)); $stream.Write($data, 0, $data.Length) } finally { $stream.Dispose() }
}
function Console-Request($requests, [string]$expectedLine, [string]$label, [int]$timeoutMs) {
    $requestPath = Join-Path $runRoot ($label + '.request.json')
    Write-NewJson $requestPath @($requests)
    $response = Invoke-Captured $node @($console, '--file', $requestPath, '--port', "$ConsolePort", '--timeout-ms', "$timeoutMs", '--expect', $expectedLine)
    Check ($response.exit_code -eq 0 -and @($response.text -split '\r?\n' | Where-Object { $_.Trim() -ceq $expectedLine }).Count -gt 0) "MINIMAP_CONSOLE_$($label.ToUpperInvariant())_FAILED: no verified response; leave the current game untouched and check Workshop template_map / console ownership"
}
function Confirm-RunningMap([string]$label) {
    $token = 'MINIMAP_TOOLS_TEMPLATE_MAP_' + [Guid]::NewGuid().ToString('N')
    $lua = "if IsServer and IsServer() and IsInToolsMode and IsInToolsMode() and GameRules and GetMapName and GetMapName() == 'template_map' then print('$token') end"
    Console-Request @(@{ name = 'dota_run_lua'; arguments = @{ code = $lua } }) $token $label 6000
    Write-Host 'MINIMAP_TOOLS_TEMPLATE_MAP_CONFIRMED'
}
function Backup-File([string]$source, [string]$root, [string]$label) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return }
    $rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $source = [IO.Path]::GetFullPath($source)
    Check ($source.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) 'MINIMAP_BACKUP_SOURCE_OUTSIDE_ADDON'
    $relative = $source.Substring($rootPrefix.Length)
    $destination = Join-Path (Join-Path $runRoot ('before/' + $label)) $relative
    if (Test-Path -LiteralPath $destination) { return }
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force
    Copy-Item -LiteralPath $source -Destination $destination
}

$game = Find-AddonRoot $GameRoot
if (-not $ContentRoot) {
    Check ($game -match '[\\/]game[\\/]dota_addons[\\/][^\\/]+$') 'MINIMAP_CONTENT_ROOT_REQUIRED'
    $ContentRoot = $game -replace '([\\/])game([\\/])dota_addons([\\/])', '${1}content${2}dota_addons${3}'
}
$content = (Resolve-Path -LiteralPath $ContentRoot).Path
if (-not $VerifyScript) { $VerifyScript = Join-Path $PSScriptRoot 'verify_minimap_sync.ps1' }
Check (Test-Path -LiteralPath $VerifyScript -PathType Leaf) 'MINIMAP_VERIFY_SCRIPT_MISSING'
$engine = [IO.Path]::GetFullPath((Join-Path $game '../../..'))
if (-not $ResourceCompiler) { $ResourceCompiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe' }
Check (Test-Path -LiteralPath $ResourceCompiler -PathType Leaf) 'MINIMAP_RESOURCECOMPILER_MISSING'
$console = Join-Path $game 'tools/map_c6/console.cjs'
Check (Test-Path -LiteralPath $console -PathType Leaf) 'MINIMAP_CONSOLE_TOOL_MISSING'
$node = (Get-Command node -CommandType Application -ErrorAction Stop).Source
$verifyArguments = @{ GameRoot = $game; ContentRoot = $content; ResourceCompiler = $ResourceCompiler; ExpectedPosX = $ExpectedPosX; ExpectedPosY = $ExpectedPosY; ExpectedScale = $ExpectedScale; AsObject = $true }
$before = & $VerifyScript @verifyArguments -SourceOnly
Check ($before.status -eq 'source_validated_only') 'MINIMAP_SOURCE_PREFLIGHT_FAILED'
$mapSource = Join-Path $content 'maps/template_map.vmap'
$mapPackage = Join-Path $game 'maps/template_map.vpk'
$beforeMapSourceHash = (Get-FileHash -LiteralPath $mapSource -Algorithm SHA256).Hash
$beforeMapPackageHash = (Get-FileHash -LiteralPath $mapPackage -Algorithm SHA256).Hash
Check ((Get-Item -LiteralPath $mapPackage).LastWriteTimeUtc -ge (Get-Item -LiteralPath $mapSource).LastWriteTimeUtc) 'MINIMAP_MAP_COMPILE_REQUIRED: compile the saved VMAP before loading it; this script never compiles maps'

if (-not $PSCmdlet.ShouldProcess('running Workshop template_map and its current overview resources', "back up overview resources, generate ${OutputSize}x${OutputSize} minimap, compile only its material if required, verify")) {
    Write-Host 'MINIMAP_CLIENT_REPAIR_PREVIEW: no console connection, generation, compilation or backup performed'
    return
}
$runRoot = Join-Path $game ('output/minimap_refresh_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $runRoot
Confirm-RunningMap 'preflight'
Write-NewJson (Join-Path $runRoot 'before.json') $before

# Back up existing resources only. No git writes, source restore, output deletion,
# VMAP replacement, VPK copy, full-map build, disconnect, restart or process kill.
foreach ($record in @($before.source_files)) {
    if ($record.path -like 'materials/*') { Backup-File (Join-Path $content $record.path) $content 'content' }
}
Backup-File (Join-Path $game 'resource/overviews/template_map.txt') $game 'game'
$activeMaterial = Join-Path $game ($before.material + '_c')
Backup-File $activeMaterial $game 'game'
if (Test-Path -LiteralPath $activeMaterial -PathType Leaf) {
    $compiledText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($activeMaterial)).Replace('\', '/')
    foreach ($match in [regex]::Matches($compiledText, 'materials/[A-Za-z0-9_./-]+\.vtex(?:_c)?')) {
        $relative = ($match.Value -replace '_c$', '') + '_c'
        Check ($relative -notmatch '(^|/)\.\.?(/|$)') 'MINIMAP_UNSAFE_COMPILED_REFERENCE'
        Backup-File (Join-Path $game $relative) $game 'game'
    }
}
# The native generator writes these names even if a custom material was linked.
# Back up both sets; after generation the *active* chain still must pass.
foreach ($item in @(@{root = $content; label = 'content'}, @{root = $game; label = 'game'})) {
    $directory = Join-Path $item.root 'materials/overviews'
    if (Test-Path -LiteralPath $directory -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $directory -File | Where-Object { $_.Name -match '^template_map(?:_tga_[0-9a-f]+)?\.(?:tga|txt|vmat|vtex|vmat_c|vtex_c)$' }) {
            Backup-File $file.FullName $item.root $item.label
        }
    }
}

# Recheck immediately before the client-only generation command. Do not change
# maps in another console while this short operation runs.
Confirm-RunningMap 'before_generate'
$generationStarted = [DateTime]::UtcNow
$done = 'MINIMAP_GENERATE_COMMANDS_DONE_' + [Guid]::NewGuid().ToString('N')
$commands = "dota_minimap_create_output_size $OutputSize`ndota_minimap_create`necho $done"
Console-Request @(@{ name = 'console_send'; arguments = @{ commands = $commands } }) $done 'generate' $ConsoleTimeoutMs

# A console echo proves command dispatch only. Require a newly written full TGA
# of the requested dimensions before accepting (or attempting material compile).
$deadline = [DateTime]::UtcNow.AddSeconds(20)
$afterSource = $null
do {
    try {
        $candidate = & $VerifyScript @verifyArguments -SourceOnly -ExpectedOutputSize $OutputSize
        $imageFile = Join-Path $content $candidate.source_image
        if ((Get-Item -LiteralPath $imageFile).LastWriteTimeUtc -ge $generationStarted) { $afterSource = $candidate; break }
    } catch { }
    Start-Sleep -Milliseconds 500
} while ([DateTime]::UtcNow -lt $deadline)
Check ($null -ne $afterSource) 'MINIMAP_GENERATION_NOT_PROVEN: expected active TGA was not freshly written; check sv_cheats / native generator in Tools, no fallback map changes were made'
Confirm-RunningMap 'after_generate'

$compiledByFallback = $false
$report = $null
try { $report = & $VerifyScript @verifyArguments -ExpectedOutputSize $OutputSize -CheckCompilerDependencies }
catch { $report = $null }
if (-not $report) {
    $currentMaterial = Join-Path $content $afterSource.material
    # Only the material resolved from the current overview is compiled. Its
    # dependency texture is handled by resourcecompiler; never compile a VMAP.
    $compile = Invoke-Captured $ResourceCompiler @('-i', $currentMaterial, '-game', (Join-Path $engine 'game/dota'), '-nop4')
    Check ($compile.exit_code -eq 0 -and $compile.text -match 'OK:\s+\d+ compiled, 0 failed, \d+ skipped') 'MINIMAP_DIRECTED_MATERIAL_COMPILE_FAILED'
    $compiledByFallback = $true
    $report = & $VerifyScript @verifyArguments -ExpectedOutputSize $OutputSize -CheckCompilerDependencies
}
Check ((Get-FileHash -LiteralPath $mapSource -Algorithm SHA256).Hash -eq $beforeMapSourceHash -and (Get-FileHash -LiteralPath $mapPackage -Algorithm SHA256).Hash -eq $beforeMapPackageHash) 'MINIMAP_MAP_CHANGED_DURING_REPAIR: stop and inspect the concurrent map change'
$report | Add-Member -NotePropertyName generation_observed -NotePropertyValue $true
$report | Add-Member -NotePropertyName tools_map_confirmed -NotePropertyValue $true
$report | Add-Member -NotePropertyName directed_compile_required -NotePropertyValue $compiledByFallback
$report | Add-Member -NotePropertyName map_source_and_package_unchanged -NotePropertyValue $true
Write-NewJson (Join-Path $runRoot 'after.json') $report
Write-Host 'MINIMAP_CLIENT_REPAIR_PASS'
Write-Host "MINIMAP_REPORT=$(Join-Path $runRoot 'after.json')"
Write-Host "MINIMAP_RESOURCE_BACKUP=$(Join-Path $runRoot 'before')"
Write-Host 'MINIMAP_VISUAL_CHECK_PENDING: inspect coast/rooms and player-marker alignment; reload client later under operator control if it retains a cached texture'
