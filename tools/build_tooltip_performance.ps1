param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$content = Join-Path $engine 'content/dota_addons/survival/panorama'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$backup = Join-Path $repo ('output/tooltip_perf_20260924/build_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$files = @('ability_tooltip', 'combat_stats')
foreach ($name in $files) {
    $source = Join-Path $repo "panorama/src/scripts/custom_game/$name.js"
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing UI source: $source" }
}
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Dota resource compiler is missing.' }
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($name in $files) {
    $destination = Join-Path $content "scripts/custom_game/$name.js"
    $artifact = Join-Path $repo "panorama/scripts/custom_game/$name.vjs_c"
    if (Test-Path -LiteralPath $destination) {
        Copy-Item -LiteralPath $destination -Destination (Join-Path $backup "$name.js")
    }
    if (Test-Path -LiteralPath $artifact) {
        Copy-Item -LiteralPath $artifact -Destination (Join-Path $backup "$name.vjs_c")
    }
    Copy-Item -LiteralPath (Join-Path $repo "panorama/src/scripts/custom_game/$name.js") -Destination $destination -Force
    $started = Get-Date
    $log = @(& $compiler -i $destination -game (Join-Path $engine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content -LiteralPath (Join-Path $backup "$name.compile.log")
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "UI compilation failed: $name; backup: $backup" }
    $result = Get-Item -LiteralPath $artifact
    if ($result.Length -eq 0 -or $result.LastWriteTime -lt $started) { throw "Compiled UI was not updated: $name" }
    Write-Output "Compiled $name ($($result.Length) bytes)"
}
Write-Output "TOOLTIP_PERFORMANCE_BUILD_PASS backup=$backup"
