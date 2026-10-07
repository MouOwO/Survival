$ErrorActionPreference='Stop'
$taskRepo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskEngine=[IO.Path]::GetFullPath((Join-Path $taskRepo '../../..'))
$taskContent=Join-Path $taskEngine 'content/dota_addons/survival/panorama'
$taskCompiler=Join-Path $taskEngine 'game/bin/win64/resourcecompiler.exe'
$taskLogs=Join-Path $taskRepo 'output/archive_ui_v3_compile'
New-Item -ItemType Directory -Force $taskLogs | Out-Null
$taskRelativeFiles=@('scripts/custom_game/archive_180de7e38b.js','scripts/custom_game/icons_remaining_5d5c1152eb.js','scripts/custom_game/archive_theme_tokens.js','scripts/custom_game/topnav_remaining_5d5c1152eb.js','styles/custom_game/archive_comfort.css','styles/custom_game/handoff_v1.css','layout/custom_game/archive.xml','layout/custom_game/survival_hud.xml','images/custom_game/archive_polish_v1/nav/building.svg')
$taskRelativeFiles+=Get-ChildItem (Join-Path $taskRepo 'panorama/src/images/custom_game/topnav_v2') -Filter '*.svg' | ForEach-Object {'images/custom_game/topnav_v2/'+$_.Name}
foreach($taskPrefix in @('friend','ex')) {for($taskIndex=1;$taskIndex -le 40;$taskIndex++){
 $taskId=$taskPrefix+'_'+('{0:d2}' -f $taskIndex)
 $taskRelativeFiles+='images/custom_game/archive_portraits_v3/'+$taskId+'.png'
 $taskRelativeFiles+='images/custom_game/archive_gpu_regular/head_v3_'+$taskId+'.vtex'
}}
foreach($taskRelative in $taskRelativeFiles){
 $taskDestination=Join-Path $taskContent $taskRelative
 New-Item -ItemType Directory -Force (Split-Path $taskDestination) | Out-Null
 Copy-Item -LiteralPath (Join-Path $taskRepo ('panorama/src/'+$taskRelative)) -Destination $taskDestination -Force
}
$taskCompleted=0
foreach($taskRelative in ($taskRelativeFiles | Where-Object {$_ -like '*.vtex'})){
 $taskResult=@(& $taskCompiler -i (Join-Path $taskContent $taskRelative) -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
 $taskExit=$LASTEXITCODE
 $taskResult | Set-Content -Encoding UTF8 (Join-Path $taskLogs ([IO.Path]::GetFileName($taskRelative)+'.log'))
 if($taskExit -ne 0 -or -not ($taskResult -match '0 failed')){throw ('Texture compilation failed: '+$taskRelative)}
 $taskCompleted++
 if($taskCompleted % 10 -eq 0){Write-Output ('PORTRAIT_TEXTURES '+$taskCompleted+'/80')}
}
foreach($taskLayout in @('archive','survival_hud')){
 $taskResult=@(& $taskCompiler -i (Join-Path $taskContent ('layout/custom_game/'+$taskLayout+'.xml')) -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
 $taskExit=$LASTEXITCODE
 $taskResult | Set-Content -Encoding UTF8 (Join-Path $taskLogs ($taskLayout+'.log'))
 if($taskExit -ne 0 -or -not ($taskResult -match '0 failed')){throw ('Layout compilation failed: '+$taskLayout)}
 $taskResult | Where-Object {$_ -match '^ OK:'} | Write-Output
}
Write-Output 'ARCHIVE_UI_V3_BUILD_PASS: 80 independent textures, archive and HUD'
