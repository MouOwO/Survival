$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$files=@('images/custom_game/shop_compact_v1/knowledge_red.png','images/custom_game/shop_compact_v1/knowledge_blue.png',
 'scripts/custom_game/remaining_5d5c1152eb.js','scripts/custom_game/shop_remaining_5d5c1152eb.js',
 'scripts/custom_game/shop_tooltip_remaining_5d5c1152eb.js','scripts/custom_game/topnav_remaining_5d5c1152eb.js',
 'scripts/custom_game/item_art_remaining_5d5c1152eb.js','styles/custom_game/remaining_5d5c1152eb.css',
 'layout/custom_game/shop_compact_assets.xml','layout/custom_game/survival_hud.xml')
foreach($rel in $files){
 $target=Join-Path $content $rel
 New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
 Copy-Item -LiteralPath (Join-Path $repo ('panorama/src/'+$rel)) -Destination $target -Force
 if($rel.EndsWith('.png')){continue}
 $output=& $compiler -i $target -game (Join-Path $engine 'game/dota') -f -nop4 2>&1
 $output | Set-Content (Join-Path $repo ('tools/shop_compact_'+[IO.Path]::GetFileName($rel)+'.log'))
 if($LASTEXITCODE -ne 0 -or -not ($output -match '0 failed')){throw "Compile failed: $rel"}
 $output | Select-String 'OK:' | ForEach-Object {$_.Line}
}
