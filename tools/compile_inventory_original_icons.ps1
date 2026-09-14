$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$dest=Join-Path $content 'images/items/survival_shop_v2'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo 'panorama/src/images/items/survival_shop_v2') -Filter '*.png' | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $dest -Force}
foreach($rel in @('layout/custom_game/inventory_original_assets.xml','scripts/custom_game/item_art_remaining_5d5c1152eb.js')){
 $target=Join-Path $content $rel
 Copy-Item -LiteralPath (Join-Path $repo ('panorama/src/'+$rel)) -Destination $target -Force
 $output=& (Join-Path $engine 'game/bin/win64/resourcecompiler.exe') -i $target -game (Join-Path $engine 'game/dota') -f -nop4 2>&1
 $output | Set-Content -LiteralPath (Join-Path $repo ('tools/inventory_original_'+[IO.Path]::GetFileName($rel)+'.log'))
 if($LASTEXITCODE -ne 0 -or -not ($output -match '0 failed')){throw "Compile failed: $rel"}
 $output | Select-String 'OK:' | ForEach-Object {$_.Line}
}
