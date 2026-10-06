$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine = [IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content = Join-Path $engine 'content/dota_addons/survival/panorama/scripts/custom_game'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$backup = Join-Path $repo ('output/weapon_max_ui/build_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$files = @('topnav_remaining_5d5c1152eb', 'combat_stats')
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Dota resource compiler is missing.' }
foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo "panorama/src/scripts/custom_game/$name.js"))) {
        throw "Missing UI source: $name"
    }
}
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($name in $files) {
    $source = Join-Path $repo "panorama/src/scripts/custom_game/$name.js"
    $destination = Join-Path $content "$name.js"
    $artifact = Join-Path $repo "panorama/scripts/custom_game/$name.vjs_c"
    foreach ($previous in @($destination, $artifact)) {
        if (Test-Path -LiteralPath $previous) {
            Copy-Item -LiteralPath $previous -Destination (Join-Path $backup ([IO.Path]::GetFileName($previous)))
        }
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $started = Get-Date
    $log = @(& $compiler -i $destination -game (Join-Path $engine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content -LiteralPath (Join-Path $backup "$name.compile.log")
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "UI compilation failed: $name" }
    $result = Get-Item -LiteralPath $artifact
    if ($result.Length -eq 0 -or $result.LastWriteTime -lt $started) { throw "Compiled UI was not updated: $name" }
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
        throw "Engine content does not match tracked source: $name"
    }
    Write-Output "Compiled $name ($($result.Length) bytes); engine content matches tracked source"
}
Write-Output "WEAPON_MAX_UI_BUILD_PASS backup=$backup"
