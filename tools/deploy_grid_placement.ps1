$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$engine = [IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content = Join-Path $engine 'content/dota_addons/Survival/panorama'
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
# Build the approved edge/corner atlas and its four native footprint phases
# before deploying a controller that can reference those particles.
& node (Join-Path $repo 'tools/build_construction_grid.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Construction grid generation failed' }
& (Join-Path $repo 'tools/compile_construction_grid.ps1')
$files = @(
    'images/custom_game/survival_grid/range_mask.png',
    'images/custom_game/survival_grid/reference_edge.png',
    'images/custom_game/survival_grid/reference_corner.png',
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
    # as standalone inputs. New dependencies compile automatically; avoid
    # forcing recompilation of the entire dependency graph in the live editor.
    if ($relative.EndsWith('.png')) { continue }
    & $compiler -i (Join-Path $content $relative) -game (Join-Path $engine 'game/dota') -fshallow -nop4
    if ($LASTEXITCODE -ne 0) { throw "Grid placement compile failed: $relative" }
}
foreach ($name in @('range_mask', 'reference_edge', 'reference_corner')) {
    $texture = Join-Path $repo "panorama/images/custom_game/survival_grid/${name}_png.vtex_c"
    if (-not (Test-Path -LiteralPath $texture)) { throw "Compiled grid texture missing: $name" }
}
Write-Output 'GRID_PLACEMENT_DEPLOY_PASS'
