param()
$ErrorActionPreference='Stop'
$taskRepo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskEngine=(Resolve-Path (Join-Path $taskRepo '../../..')).Path
$taskContent=Join-Path $taskEngine 'content/dota_addons/survival/panorama/scripts/custom_game'
$taskGame=Join-Path $taskRepo 'panorama/scripts/custom_game'
$taskCompiler=Join-Path $taskEngine 'game/bin/win64/resourcecompiler.exe'
$taskCheckpoint=Join-Path $taskRepo ('output/late_combat_20261008/ui_build_'+(Get-Date -Format yyyyMMdd_HHmmss))
$taskNames=@('combat_stats','ability_tooltip','ui_snapshot_cache','survival_ui','production_progress','survival_grid_placement','world_overlay_visibility','hero_world_health_bar','tower_rank_ui','topnav_remaining_5d5c1152eb','handoff_hud')
$taskRecords=@()
New-Item -ItemType Directory -Force -Path $taskCheckpoint | Out-Null
foreach($taskName in $taskNames) {
 $taskSource=Join-Path $taskRepo "panorama/src/scripts/custom_game/$taskName.js"
 $taskDestination=Join-Path $taskContent "$taskName.js"
 $taskArtifact=Join-Path $taskGame "$taskName.vjs_c"
 if(-not(Test-Path -LiteralPath $taskSource)){throw "Missing source: $taskName"}
 & node --check $taskSource
 if($LASTEXITCODE -ne 0){throw "Syntax error: $taskName"}
 $taskRecord=[pscustomobject]@{name=$taskName;source=$taskSource;content=$taskDestination;artifact=$taskArtifact;contentExisted=(Test-Path -LiteralPath $taskDestination);artifactExisted=(Test-Path -LiteralPath $taskArtifact)}
 if($taskRecord.contentExisted){Copy-Item -LiteralPath $taskDestination -Destination (Join-Path $taskCheckpoint "$taskName.content.js")}
 if($taskRecord.artifactExisted){Copy-Item -LiteralPath $taskArtifact -Destination (Join-Path $taskCheckpoint "$taskName.game.vjs_c")}
 $taskRecords+=$taskRecord
}
try {
 foreach($taskRecord in $taskRecords) {
  Copy-Item -LiteralPath $taskRecord.source -Destination $taskRecord.content -Force
  $taskStarted=Get-Date
  $taskLog=@(& $taskCompiler -i $taskRecord.content -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
  $taskCode=$LASTEXITCODE
  $taskLog | Set-Content -LiteralPath (Join-Path $taskCheckpoint ($taskRecord.name+'.compile.log'))
  if($taskCode -ne 0 -or -not($taskLog -match '0 failed')){throw "Compile failed: $($taskRecord.name)"}
  $taskResult=Get-Item -LiteralPath $taskRecord.artifact
  if($taskResult.Length -le 0 -or $taskResult.LastWriteTime -lt $taskStarted){throw "Stale/empty artifact: $($taskRecord.name)"}
  if((Get-FileHash -LiteralPath $taskRecord.source).Hash -ne (Get-FileHash -LiteralPath $taskRecord.content).Hash){throw "Source/content mismatch: $($taskRecord.name)"}
  Write-Output ('UI_COMPILE_PASS '+$taskRecord.name)
 }
 $taskRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskCheckpoint 'manifest.json')
 Write-Output ('UI_CHECKPOINT '+$taskCheckpoint)
} catch {
 foreach($taskRecord in $taskRecords) {
  if($taskRecord.contentExisted){Copy-Item -LiteralPath (Join-Path $taskCheckpoint ($taskRecord.name+'.content.js')) -Destination $taskRecord.content -Force}
  elseif(Test-Path -LiteralPath $taskRecord.content){Remove-Item -LiteralPath $taskRecord.content}
  if($taskRecord.artifactExisted){Copy-Item -LiteralPath (Join-Path $taskCheckpoint ($taskRecord.name+'.game.vjs_c')) -Destination $taskRecord.artifact -Force}
  elseif(Test-Path -LiteralPath $taskRecord.artifact){Remove-Item -LiteralPath $taskRecord.artifact}
 }
 throw
}
