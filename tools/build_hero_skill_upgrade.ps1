param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$content = Join-Path $engine 'content/dota_addons/survival/panorama'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$backup = Join-Path $repo ('output/hero_skill_upgrade/before_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$files = @(
    'scripts/custom_game/hero_skill_upgrade.js',
    'scripts/custom_game/ability_tooltip.js',
    'styles/custom_game/ability_tooltip.css',
    'scripts/custom_game/hero_skill_ui.js',
    'styles/custom_game/hero_skill_ui.css',
    'layout/custom_game/hero_skill_ui.xml',
    'styles/custom_game/common/ui_typography.css',
    'layout/custom_game/survival_hud.xml'
)
foreach ($relative in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo ('panorama/src/' + $relative)))) {
        throw "Missing UI source: $relative"
    }
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
    if ($LASTEXITCODE -ne 0 -or -not ($log -match '0 failed')) { throw "Hero skill UI compilation failed: $relative" }
    $log | Where-Object { $_ -match 'RESOURCE COMPILE|OK:|ERROR:|failed' } | Write-Output
}
Write-Output 'HERO_SKILL_UPGRADE_BUILD_PASS'
