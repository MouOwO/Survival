param([ValidateSet('presentation','idle','worldtitle','loading','health','selection','hotkey')][string]$Group='presentation')
$ErrorActionPreference='Stop'
$taskRepo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskEngine=(Resolve-Path (Join-Path $taskRepo '../../..')).Path
$taskCompiler=Join-Path $taskEngine 'game/bin/win64/resourcecompiler.exe'
$taskNames=switch($Group){
 'idle' {@('survival_ui','commerce_actions')}
 'worldtitle' {@('title_world_overlap_v30')}
 'loading' {@('startup_loading')}
 'health' {@('hero_world_health_bar')}
 'hotkey' {@('topnav_remaining_5d5c1152eb')}
 'selection' {@('geometry_remaining_5d5c1152eb','topnav_remaining_5d5c1152eb','production_progress')}
 default {@('topnav_remaining_5d5c1152eb','production_progress','lumberjack_fusion_queue','inventory_tooltip')}
}
$taskCheckpoint=Join-Path $taskRepo ('output/four_operation_extreme_20261012/ui_'+$Group+'_build_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
New-Item -ItemType Directory -Force -Path $taskCheckpoint | Out-Null
$taskRecords=@()
foreach($taskName in $taskNames){
 $taskSource=Join-Path $taskRepo "panorama/src/scripts/custom_game/$taskName.js"
 $taskContent=Join-Path $taskEngine "content/dota_addons/survival/panorama/scripts/custom_game/$taskName.js"
 $taskArtifact=Join-Path $taskRepo "panorama/scripts/custom_game/$taskName.vjs_c"
 & node --check $taskSource
 if($LASTEXITCODE -ne 0){throw "JS syntax failed: $taskName"}
 $taskRecord=[pscustomobject]@{name=$taskName;source=$taskSource;content=$taskContent;artifact=$taskArtifact
  sourceHash=(Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash
  contentExisted=(Test-Path -LiteralPath $taskContent -PathType Leaf);artifactExisted=(Test-Path -LiteralPath $taskArtifact -PathType Leaf)
  contentHashBefore=$null;artifactHashBefore=$null;artifactHashAfter=$null
  contentBackup=(Join-Path $taskCheckpoint "$taskName.content.js");artifactBackup=(Join-Path $taskCheckpoint "$taskName.game.vjs_c");status='backed_up'}
 if($taskRecord.contentExisted){$taskRecord.contentHashBefore=(Get-FileHash -LiteralPath $taskContent).Hash;Copy-Item -LiteralPath $taskContent -Destination $taskRecord.contentBackup}
 if($taskRecord.artifactExisted){$taskRecord.artifactHashBefore=(Get-FileHash -LiteralPath $taskArtifact).Hash;Copy-Item -LiteralPath $taskArtifact -Destination $taskRecord.artifactBackup}
 $taskRecords+=$taskRecord
}
$taskManifest=Join-Path $taskCheckpoint 'manifest.json'
$taskRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskManifest
try {
 foreach($taskRecord in $taskRecords){
  Copy-Item -LiteralPath $taskRecord.source -Destination $taskRecord.content -Force
  $taskStarted=Get-Date
  $taskLog=@(& $taskCompiler -i $taskRecord.content -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
  $taskExit=$LASTEXITCODE
  $taskLog | Set-Content -LiteralPath (Join-Path $taskCheckpoint "$($taskRecord.name).compile.log")
  if($taskExit -ne 0 -or -not($taskLog -match '0 failed')){throw "Compile failed: $($taskRecord.name)"}
  $taskResult=Get-Item -LiteralPath $taskRecord.artifact
  if($taskResult.Length -le 0 -or $taskResult.LastWriteTime -lt $taskStarted){throw 'Stale artifact'}
  if((Get-FileHash -LiteralPath $taskRecord.content).Hash -ne $taskRecord.sourceHash -or (Get-FileHash -LiteralPath $taskRecord.source).Hash -ne $taskRecord.sourceHash){throw 'Source changed during build'}
  $taskRecord.artifactHashAfter=(Get-FileHash -LiteralPath $taskRecord.artifact).Hash
  $taskRecord.status='compiled'
 }
 $taskRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskManifest
 Write-Output ('PERF_UI_COMPILE_PASS files='+$taskRecords.Count+' checkpoint='+$taskCheckpoint)
} catch {
 $taskFailure=$_; $taskRestoreErrors=@()
 foreach($taskRecord in $taskRecords){
  foreach($taskRestore in @(
   @{path=$taskRecord.content;backup=$taskRecord.contentBackup;existed=$taskRecord.contentExisted;hash=$taskRecord.contentHashBefore},
   @{path=$taskRecord.artifact;backup=$taskRecord.artifactBackup;existed=$taskRecord.artifactExisted;hash=$taskRecord.artifactHashBefore}
  )){
   try {
    if($taskRestore.existed){Copy-Item -LiteralPath $taskRestore.backup -Destination $taskRestore.path -Force; if((Get-FileHash -LiteralPath $taskRestore.path).Hash -ne $taskRestore.hash){throw 'Rollback mismatch'}}
    elseif(Test-Path -LiteralPath $taskRestore.path){Remove-Item -LiteralPath $taskRestore.path}
   } catch {$taskRestoreErrors+=[string]$_}
  }
  $taskRecord.status=if($taskRestoreErrors.Count){'rollback_failed'}else{'rolled_back'}
 }
 $taskRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskManifest
 if($taskRestoreErrors.Count){throw ($taskFailure.ToString()+'; rollback errors: '+($taskRestoreErrors -join '; '))}
 throw $taskFailure
}
