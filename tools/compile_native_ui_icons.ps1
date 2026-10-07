$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine = [IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$env:PYTHONIOENCODING = 'utf-8'
& $python -X utf8 (Join-Path $PSScriptRoot 'sync_native_ui_icons.py')
if ($LASTEXITCODE -ne 0) { throw 'Native icon source synchronization failed' }
$files = @('layout/custom_game/survival_hud.xml', 'layout/custom_game/archive.xml', 'layout/custom_game/rogue_reward_ui.xml')
$names = @('native_ui_icons', 'item_art_remaining_5d5c1152eb', 'inventory_tooltip', 'topnav_remaining_5d5c1152eb', 'minimap_shortcuts', 'production_progress', 'shop_ui', 'rogue_art_remaining_5d5c1152eb', 'ability_tooltip')
$files += $names | ForEach-Object { "scripts/custom_game/$_.js" }
foreach ($relative in $files) {
    $source = Join-Path $engine "content/dota_addons/survival/panorama/$relative"
    $output = & (Join-Path $engine 'game/bin/win64/resourcecompiler.exe') -i $source -game (Join-Path $engine 'game/dota') -fshallow -nop4 2>&1
    if ($LASTEXITCODE -ne 0 -or $output -match 'ERROR|LoadKV3') { throw "Compile failed: $relative`n$output" }
    if (-not ($output -match '0 failed')) { throw "Compiler did not report completion: $relative`n$output" }
    Write-Output "NATIVE_UI_COMPILED $relative"
}
