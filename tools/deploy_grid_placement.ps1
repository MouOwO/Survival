$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$engine = [IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content = Join-Path $engine 'content/dota_addons/Survival/panorama'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$files = @(
    'images/custom_game/survival_grid/range_mask.png',
    'images/custom_game/survival_grid/corner.svg',
    'styles/custom_game/survival_grid_placement.css',
    'scripts/custom_game/survival_static_grid.js',
    'scripts/custom_game/survival_grid_state.js',
    'scripts/custom_game/survival_grid_placement.js',
    'layout/custom_game/survival_grid_placement.xml'
)
$backup = Join-Path $repo ('tmp/grid_reference/content_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
foreach ($relative in $files) {
    $source = Join-Path $repo ('panorama/src/' + $relative)
    $target = Join-Path $content $relative
    if (Test-Path -LiteralPath $target) {
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Copy-Item -LiteralPath $target -Destination (Join-Path $backup ([IO.Path]::GetFileName($target)))
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}
foreach ($relative in $files) {
    # PNG inputs compile as dependencies of the CSS into *_png.vtex_c, not
    # as standalone resourcecompiler inputs. Use -f to include dependencies.
    if ($relative.EndsWith('.png')) { continue }
    & $compiler -i (Join-Path $content $relative) -game (Join-Path $engine 'game/dota') -f -nop4
    if ($LASTEXITCODE -ne 0) { throw "Grid placement compile failed: $relative" }
}
$maskTexture = Join-Path $repo 'panorama/images/custom_game/survival_grid/range_mask_png.vtex_c'
if (-not (Test-Path -LiteralPath $maskTexture)) { throw 'Compiled grid opacity texture missing' }
Write-Output 'GRID_PLACEMENT_DEPLOY_PASS'
