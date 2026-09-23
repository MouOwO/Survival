param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$content = Join-Path $engine 'content/dota_addons/survival'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$source = Join-Path $repo 'panorama/src'
if (-not (Test-Path -LiteralPath $content) -or -not (Test-Path -LiteralPath $compiler)) {
    throw 'Dota Workshop Tools content directory or resourcecompiler.exe is missing.'
}
$files = @(
    'layout/custom_game/startup_loading.xml',
    'layout/custom_game/custom_loading_screen.xml',
    'layout/custom_game/custom_ui_manifest.xml',
    'styles/custom_game/startup_loading.css',
    'scripts/custom_game/startup_loading.js',
    'images/custom_game/loading/server_loading_background.png'
)
# Deliberately sync only this feature; unrelated game/content assets are preserved.
foreach ($relative in $files) {
    $inputFile = Join-Path $source $relative
    $destination = Join-Path (Join-Path $content 'panorama') $relative
    if (-not (Test-Path -LiteralPath $inputFile)) { throw "Missing source: $relative" }
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath $inputFile -Destination $destination -Force
}
foreach ($relative in @($files | Where-Object { $_ -notlike '*.png' })) {
    # PNGs are compiled as XML image dependencies, never as standalone inputs.
    # Incremental compilation avoids force-rebuilding the manifest's other UI.
    $buildLog = @(& $compiler -i (Join-Path (Join-Path $content 'panorama') $relative) -game (Join-Path $engine 'game/dota') -nop4)
    $buildLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|FAIL|WARNING|OK:|Failed to' } | Write-Output
    if ($LASTEXITCODE -ne 0) { throw "Loading screen compilation failed: $relative" }
}
Write-Host 'STARTUP_LOADING_BUILD_PASS'
