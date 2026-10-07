$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskEngine=[IO.Path]::GetFullPath((Join-Path $taskRoot '../../..'))
$taskContent=Join-Path $taskEngine 'content/dota_addons/survival/panorama'
$taskCompiler=Join-Path $taskEngine 'game/bin/win64/resourcecompiler.exe'
$taskAssetDir=Join-Path $taskRoot 'panorama/src/images/custom_game/reward_art_v5'
$taskTargetDir=Join-Path $taskContent 'images/custom_game/reward_art_v5'
New-Item -ItemType Directory -Force -Path $taskTargetDir | Out-Null
Get-ChildItem -LiteralPath $taskAssetDir -File | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $taskTargetDir $_.Name) -Force}
$taskFiles=@(
'scripts/custom_game/topnav_remaining_5d5c1152eb.js',
'scripts/custom_game/remaining_5d5c1152eb.js',
'scripts/custom_game/shop_remaining_5d5c1152eb.js',
'scripts/custom_game/lottery_handoff_bb9968eef7.js',
'scripts/custom_game/item_art_remaining_5d5c1152eb.js',
'scripts/custom_game/icons_remaining_5d5c1152eb.js',
'scripts/custom_game/daily_remaining_5d5c1152eb.js',
'styles/custom_game/common/ui_components.css',
'styles/custom_game/topnav_refinement_v5.css',
'layout/custom_game/archive.xml',
'layout/custom_game/survival_hud.xml')
foreach($taskFile in $taskFiles){Copy-Item -LiteralPath (Join-Path $taskRoot ('panorama/src/'+$taskFile)) -Destination (Join-Path $taskContent $taskFile) -Force}
$taskLog=Join-Path $taskRoot 'output/reward_ui_v5_compile.log'
[IO.File]::WriteAllText($taskLog,'')
$taskCount=0
foreach($taskTexture in (Get-ChildItem -LiteralPath $taskTargetDir -Filter '*.vtex')){
 $taskOutput=@(& $taskCompiler -i $taskTexture.FullName -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
 $taskExit=$LASTEXITCODE
 $taskOutput | Add-Content -LiteralPath $taskLog
 if($taskExit -ne 0 -or -not ($taskOutput -match '0 failed')){throw ('Texture compile failed: '+$taskTexture.Name)}
 $taskCount++
 if($taskCount%20 -eq 0){Write-Output ("Textures compiled: "+$taskCount)}
}
foreach($taskLayout in @('archive','survival_hud')){
 $taskOutput=@(& $taskCompiler -i (Join-Path $taskContent ('layout/custom_game/'+$taskLayout+'.xml')) -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
 $taskExit=$LASTEXITCODE
 $taskOutput | Add-Content -LiteralPath $taskLog
 if($taskExit -ne 0 -or -not ($taskOutput -match '0 failed')){throw ('Layout compile failed: '+$taskLayout)}
 $taskOutput | Select-String 'OK:' | ForEach-Object {$_.Line}
}
Write-Output ("REWARD_UI_V5_COMPILE_PASS: "+$taskCount+" textures and both layouts")
