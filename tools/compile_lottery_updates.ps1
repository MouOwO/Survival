$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$files=@('scripts/custom_game/lottery_handoff_bb9968eef7.js','scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','styles/custom_game/remaining_5d5c1152eb.css')
$files+=@('cultivation','dragon_knight','summer') | ForEach-Object { 'images/custom_game/lottery_pool_scenes_v1/'+$_+'.png' }
$files+='layout/custom_game/lottery_pool_scene_assets.xml'
foreach($rel in $files) {
    $target=Join-Path $content $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo ('panorama/src/'+$rel)) -Destination $target -Force
    # Panorama's layout compiler discovers PNG dependencies and emits *_png.vtex_c.
    if($rel.EndsWith('.png')) { continue }
    $output=& $compiler -i $target -game (Join-Path $engine 'game/dota') -f -nop4 2>&1
    $output | Set-Content (Join-Path $repo ('tools/lottery_update_'+[IO.Path]::GetFileName($rel)+'.log'))
    if($LASTEXITCODE -ne 0 -or -not ($output -match '0 failed')) { throw "Compile failed: $rel" }
    $output | Select-String 'OK:' | ForEach-Object {$_.Line}
}
