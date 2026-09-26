param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/survival/panorama'
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$backup=Join-Path $repo ('output/native_hud_refresh_20260926/build_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
$files=@('scripts/custom_game/production_progress.js','scripts/custom_game/combat_stats.js','scripts/custom_game/item_art_remaining_5d5c1152eb.js','layout/custom_game/native_hud_icon_assets.xml')
$files+=@('scripts/custom_game/rogue_art_remaining_5d5c1152eb.js','scripts/custom_game/topnav_remaining_5d5c1152eb.js','scripts/custom_game/handoff_hud.js','scripts/custom_game/minimap_shortcuts.js','scripts/custom_game/ability_tooltip.js','layout/custom_game/survival_hud.xml')
foreach($folder in @('survival_shop_v2','survival_unified')){Get-ChildItem -LiteralPath (Join-Path $repo ('panorama/src/images/items/'+$folder)) -Filter '*.png' | ForEach-Object {$files+='images/items/'+$folder+'/'+$_.Name}}
Get-ChildItem -LiteralPath (Join-Path $repo 'panorama/src/images/spellicons/survival/native') -Filter '*.png' | ForEach-Object {$files+='images/spellicons/survival/native/'+$_.Name}
foreach($relative in $files){
 $src=Join-Path $repo ('panorama/src/'+$relative);$dst=Join-Path $content $relative
 if(!(Test-Path -LiteralPath $src)){throw "Missing source: $relative"}
 if(Test-Path -LiteralPath $dst){$saved=Join-Path $backup $relative;New-Item -ItemType Directory -Force (Split-Path $saved) | Out-Null;Copy-Item -LiteralPath $dst -Destination $saved}
 New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
 Copy-Item -LiteralPath $src -Destination $dst -Force
}
New-Item -ItemType Directory -Force $backup | Out-Null
foreach($relative in @('layout/custom_game/native_hud_icon_assets.xml','layout/custom_game/survival_hud.xml')){
 $log=@(& $compiler -i (Join-Path $content $relative) -game (Join-Path $engine 'game/dota') -f -nop4 2>&1)
 $exitCode=$LASTEXITCODE
 $log | Set-Content -Encoding UTF8 (Join-Path $backup ([IO.Path]::GetFileName($relative)+'.log'))
 if($exitCode -ne 0 -or -not ($log -match '0 failed')){throw "Resource compilation failed: $relative (see $backup)"}
 $log | Where-Object {$_ -match 'RESOURCE COMPILE|failed'} | Write-Output
}
$missing=@()
Get-ChildItem -LiteralPath (Join-Path $repo 'panorama/src/images/spellicons/survival/native') -Filter '*.png' | ForEach-Object {
 if(!(Test-Path -LiteralPath (Join-Path $repo ('panorama/images/spellicons/survival/native/'+$_.BaseName+'_png.vtex_c')))){$missing+=$_.Name}
}
if($missing.Count){throw ('Missing compiled icons: '+($missing -join ','))}
Write-Output 'NATIVE_HUD_ICONS_BUILD_PASS'
