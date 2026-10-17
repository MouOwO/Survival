param()
$ErrorActionPreference='Stop'
$taskRepo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskEngine=(Resolve-Path (Join-Path $taskRepo '../../..')).Path
$taskName='hero_world_health_bar'
$taskSource=Join-Path $taskRepo "panorama/src/scripts/custom_game/$taskName.js"
$taskContent=Join-Path $taskEngine "content/dota_addons/survival/panorama/scripts/custom_game/$taskName.js"
$taskArtifact=Join-Path $taskRepo "panorama/scripts/custom_game/$taskName.vjs_c"
$taskCompiler=Join-Path $taskEngine 'game/bin/win64/resourcecompiler.exe'
$taskNode=(Get-Command node -ErrorAction Stop).Source
if(-not(Test-Path -LiteralPath $taskSource -PathType Leaf)){throw "Missing source: $taskSource"}
if(-not(Test-Path -LiteralPath $taskCompiler -PathType Leaf)){throw "Missing compiler: $taskCompiler"}
& $taskNode --check $taskSource
if($LASTEXITCODE -ne 0){throw "Syntax error: $taskName"}
$taskCheckpoint=Join-Path $taskRepo ('output/four_operation_extreme_20261012/worldbar_visibility_cache_build_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $taskCheckpoint | Out-Null
$taskManifest=Join-Path $taskCheckpoint 'manifest.json'
$taskRecord=[pscustomobject]@{
 name=$taskName;source=$taskSource;content=$taskContent;artifact=$taskArtifact
 sourceHash=(Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash
 contentExisted=(Test-Path -LiteralPath $taskContent -PathType Leaf)
 artifactExisted=(Test-Path -LiteralPath $taskArtifact -PathType Leaf)
 contentHashBefore=$null;artifactHashBefore=$null;contentHashAfter=$null;artifactHashAfter=$null
 contentBackup=(Join-Path $taskCheckpoint "$taskName.content.js")
 artifactBackup=(Join-Path $taskCheckpoint "$taskName.game.vjs_c")
 status='backed_up';error=$null
}
if($taskRecord.contentExisted){$taskRecord.contentHashBefore=(Get-FileHash -LiteralPath $taskContent -Algorithm SHA256).Hash;Copy-Item -LiteralPath $taskContent -Destination $taskRecord.contentBackup}
if($taskRecord.artifactExisted){$taskRecord.artifactHashBefore=(Get-FileHash -LiteralPath $taskArtifact -Algorithm SHA256).Hash;Copy-Item -LiteralPath $taskArtifact -Destination $taskRecord.artifactBackup}
$taskRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskManifest
try {
 # Exactly one source and one compiled artifact: no layout/CSS or other UI sync.
 Copy-Item -LiteralPath $taskSource -Destination $taskContent -Force
 $taskStarted=Get-Date
 $taskLog=@(& $taskCompiler -i $taskContent -game (Join-Path $taskEngine 'game/dota') -f -nop4 2>&1)
 $taskCode=$LASTEXITCODE
 $taskLog | Set-Content -LiteralPath (Join-Path $taskCheckpoint "$taskName.compile.log")
 if($taskCode -ne 0 -or -not($taskLog -match '0 failed')){throw "Compile failed: $taskName (exit $taskCode)"}
 $taskResult=Get-Item -LiteralPath $taskArtifact
 if($taskResult.Length -le 0 -or $taskResult.LastWriteTime -lt $taskStarted){throw "Stale/empty artifact: $taskName"}
 $taskRecord.contentHashAfter=(Get-FileHash -LiteralPath $taskContent -Algorithm SHA256).Hash
 if((Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash -ne $taskRecord.sourceHash -or $taskRecord.contentHashAfter -ne $taskRecord.sourceHash){throw "Source changed during build or content mismatch: $taskName"}
 $taskRecord.artifactHashAfter=(Get-FileHash -LiteralPath $taskArtifact -Algorithm SHA256).Hash
 $taskRecord.status='compiled'
 $taskRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskManifest
 Write-Output ('UI_COMPILE_PASS '+$taskName)
 Write-Output ('UI_CHECKPOINT '+$taskCheckpoint)
} catch {
 $taskFailure=$_;$taskRecord.error=[string]$taskFailure;$taskRestoreErrors=@()
 foreach($taskRestore in @(
  [pscustomobject]@{path=$taskContent;backup=$taskRecord.contentBackup;existed=$taskRecord.contentExisted;hash=$taskRecord.contentHashBefore},
  [pscustomobject]@{path=$taskArtifact;backup=$taskRecord.artifactBackup;existed=$taskRecord.artifactExisted;hash=$taskRecord.artifactHashBefore}
 )) {
  try {
   if($taskRestore.existed){Copy-Item -LiteralPath $taskRestore.backup -Destination $taskRestore.path -Force;if((Get-FileHash -LiteralPath $taskRestore.path -Algorithm SHA256).Hash -ne $taskRestore.hash){throw "Rollback hash mismatch: $($taskRestore.path)"}}
   elseif(Test-Path -LiteralPath $taskRestore.path){Remove-Item -LiteralPath $taskRestore.path}
  } catch {$taskRestoreErrors+=[string]$_}
 }
 $taskRecord.status=if($taskRestoreErrors.Count){'rollback_failed'}else{'rolled_back'}
 $taskRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskManifest
 Write-Output ('UI_CHECKPOINT '+$taskCheckpoint)
 if($taskRestoreErrors.Count){throw ($taskRecord.error+'; rollback errors: '+($taskRestoreErrors -join '; '))}
 throw $taskFailure
}
