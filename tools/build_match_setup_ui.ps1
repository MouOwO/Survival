param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$content = Join-Path $engine 'content/dota_addons/survival/panorama'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$source = Join-Path $repo 'panorama/src'
if (-not (Test-Path -LiteralPath $content) -or -not (Test-Path -LiteralPath $compiler)) {
    throw 'Dota Workshop Tools content directory or resourcecompiler.exe is missing.'
}
$files = @(
    'layout/custom_game/startup_loading.xml',
    'layout/custom_game/custom_loading_screen.xml',
    'layout/custom_game/survival_hud.xml',
    'scripts/custom_game/startup_loading.js',
    'scripts/custom_game/survival_ui.js',
    'styles/custom_game/startup_loading.css',
    'styles/custom_game/archive_difficulty.css'
)
# Existing shared components and textures are referenced by these layouts. Copy
# only the matching components; never replace unrelated HUD/art source files.
$shared = @(
    'scripts/custom_game/common/ui_components.js',
    'scripts/custom_game/common/ui_registry.js',
    'scripts/custom_game/ui_layers.js',
    'scripts/custom_game/common/ui_typography.js',
    'styles/custom_game/common/ui_components.css',
    'styles/custom_game/common/ui_typography.css'
)
foreach ($relative in @($files + $shared)) {
    $inputFile = Join-Path $source $relative
    if (-not (Test-Path -LiteralPath $inputFile)) { throw "Missing source: $relative" }
    $destination = Join-Path $content $relative
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath $inputFile -Destination $destination -Force
}
foreach ($relative in @($files + $shared)) {
    $buildLog = @(& $compiler -i (Join-Path $content $relative) -game (Join-Path $engine 'game/dota') -nop4)
    $buildLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|FAIL|WARNING|OK:|Failed to' } | Write-Output
    if ($LASTEXITCODE -ne 0) { throw "Match setup compilation failed: $relative" }
}
Write-Host 'MATCH_SETUP_UI_BUILD_PASS'
