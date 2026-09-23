param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$content = Join-Path $engine 'content/dota_addons/survival/panorama'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$backup = Join-Path $repo ('output/multiselect_portraits/before_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$files = @(
    'scripts/custom_game/multiselect_portraits.js',
    'scripts/custom_game/combat_stats.js',
    'scripts/custom_game/topnav_remaining_5d5c1152eb.js',
    'layout/custom_game/survival_hud.xml'
)
foreach ($relative in $files) {
    $source = Join-Path $repo ('panorama/src/' + $relative)
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing source: $relative" }
}
foreach ($relative in $files) {
    $destination = Join-Path $content $relative
    if (Test-Path -LiteralPath $destination) {
        $saved = Join-Path $backup $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $saved) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $saved
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo ('panorama/src/' + $relative)) -Destination $destination -Force
}
foreach ($relative in $files) {
    $log = @(& $compiler -i (Join-Path $content $relative) -game (Join-Path $engine 'game/dota') -f -nop4 2>&1)
    $log | Set-Content (Join-Path $backup ([IO.Path]::GetFileName($relative) + '.compile.log'))
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Multi-selection UI compilation failed: $relative" }
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|OK:|ERROR:|failed' } | Write-Output
}
Write-Output 'MULTISELECT_PORTRAITS_BUILD_PASS'
