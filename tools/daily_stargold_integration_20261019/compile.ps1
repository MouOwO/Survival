[CmdletBinding()]
param(
 [string]$Plan='output/daily_stargold_integration_20261019/compile_plan.json',
 [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$resourceRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resourceEngine=[IO.Path]::GetFullPath((Join-Path $resourceRepo '../../..'))
$resourceContent=[IO.Path]::GetFullPath((Join-Path $resourceEngine 'content/dota_addons/Survival/panorama'))
$resourceCompiler=Join-Path $resourceEngine 'game/bin/win64/resourcecompiler.exe'
$resourcePlanFile=[IO.Path]::GetFullPath((Join-Path $resourceRepo $Plan))
$resourceAllowedPlanRoots=@(
 (Join-Path $resourceRepo 'output/daily_stargold_integration_20261019'),
 (Join-Path $resourceRepo 'design_refs/daily_stargold_integration_20261019')
)
$resourcePlanInScope=$false
foreach($planRoot in $resourceAllowedPlanRoots){
 if($resourcePlanFile.StartsWith($planRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$resourcePlanInScope=$true}
}
if(-not $resourcePlanInScope){throw 'Compile plan must be inside this task output directory.'}
$resourceAllowedSources=@(
 'scripts/custom_game/daily_remaining_5d5c1152eb.js',
 'scripts/custom_game/daily_gw2_data.js',
 'styles/custom_game/daily_gw2.css',
 'layout/custom_game/daily_gw2_assets.xml'
)
$resourcePlan=Get-Content -LiteralPath $resourcePlanFile -Raw -Encoding UTF8|ConvertFrom-Json
$resourceBackup=Join-Path $resourceRepo ('output/daily_stargold_integration_20261019/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$resourceRecords=@()
$resourceSucceeded=$false
$resourceFailure=$null
$resourceRestoreErrors=@()
function Get-ResourceHash([string]$target){
 if(Test-Path -LiteralPath $target -PathType Leaf){return (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}
 return $null
}
function Assert-ResourceHash([string]$target,$expected,[string]$stage){
 if((Get-ResourceHash $target) -ne $expected){throw "Concurrent change during ${stage}: $target. Current file retained; backups: $resourceBackup"}
}
function Save-ResourceManifest {
 [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');success=$resourceSucceeded;failure=$resourceFailure;backup=$resourceBackup;plan=$resourcePlanFile;restoreErrors=$resourceRestoreErrors;records=$resourceRecords}|
  ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $resourceBackup 'manifest.json') -Encoding UTF8
}
$resourceSeen=@{}
foreach($entry in $resourcePlan.files){
 $relative=[string]$entry.path
 if($relative -cnotin $resourceAllowedSources -or $resourceSeen.ContainsKey($relative)){throw "Unexpected or duplicate source in daily Stargold compile scope: $relative"}
 $resourceSeen[$relative]=$true
 $source=[IO.Path]::GetFullPath((Join-Path $resourceRepo ('panorama/src/'+$relative)))
 $content=[IO.Path]::GetFullPath((Join-Path $resourceContent $relative))
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'
 $artifact=[IO.Path]::GetFullPath((Join-Path $resourceRepo ('panorama/'+$compiled)))
 foreach($pair in @(@($source,(Join-Path $resourceRepo 'panorama/src')),@($content,$resourceContent),@($artifact,(Join-Path $resourceRepo 'panorama')))){
  if(-not $pair[0].StartsWith($pair[1]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Compile path escaped intended root: $relative"}
 }
 $sourceHash=Get-ResourceHash $source
 if(-not $sourceHash -or [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $entry.sha256 -cne $sourceHash){throw "Reviewed source hash missing or changed: $relative"}
 $resourceRecords+=[pscustomobject]@{
  relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=$sourceHash
  contentBeforeHash=(Get-ResourceHash $content);artifactBeforeHash=(Get-ResourceHash $artifact)
  sourceBackup=(Join-Path $resourceBackup ('source/'+$relative));contentBackup=(Join-Path $resourceBackup ('content/'+$relative));runtimeBackup=(Join-Path $resourceBackup ('runtime/'+$compiled))
  compilerLog=(Join-Path $resourceBackup (($relative -replace '/','_')+'.log'))
  contentOwnedHash=$null;artifactOwnedHash=$null;compiledHash=$null;runtimeAttempted=$false;contentRestored=$false;artifactRestored=$false
 }
}
if(-not $resourceRecords.Count){throw 'Compile plan is empty.'}
if($CheckOnly){Write-Output ('DAILY_STARGOLD_COMPILE_SCOPE_PASS '+$resourceRecords.Count+' reviewed source files');return}
if(-not(Test-Path -LiteralPath $resourceCompiler -PathType Leaf)){throw 'Native resourcecompiler is unavailable.'}
try{
 foreach($record in $resourceRecords){
  foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){
   [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
  }
  Assert-ResourceHash $record.source $record.sourceHash 'source snapshot'
  Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
  Assert-ResourceHash $record.sourceBackup $record.sourceHash 'source snapshot'
  Assert-ResourceHash $record.source $record.sourceHash 'source snapshot'
  foreach($kind in @('content','artifact')){
   $beforeHash=$record.($kind+'BeforeHash')
   Assert-ResourceHash $record.$kind $beforeHash "$kind snapshot"
   if($beforeHash){
    $backupPath=if($kind -eq 'artifact'){$record.runtimeBackup}else{$record.contentBackup}
    Copy-Item -LiteralPath $record.$kind -Destination $backupPath
    Assert-ResourceHash $backupPath $beforeHash "$kind snapshot"
   }
   Assert-ResourceHash $record.$kind $beforeHash "$kind snapshot"
  }
 }
 Save-ResourceManifest
 foreach($record in $resourceRecords){
  Assert-ResourceHash $record.source $record.sourceHash 'before compile'
  Assert-ResourceHash $record.content $record.contentBeforeHash 'before content staging'
  Assert-ResourceHash $record.artifact $record.artifactBeforeHash 'before compile'
  [void][IO.Directory]::CreateDirectory((Split-Path -Parent $record.content))
  Copy-Item -LiteralPath $record.sourceBackup -Destination $record.content -Force
  $record.contentOwnedHash=$record.sourceHash
  Assert-ResourceHash $record.content $record.contentOwnedHash 'content staging'
  Assert-ResourceHash $record.source $record.sourceHash 'before native compile'
  Assert-ResourceHash $record.artifact $record.artifactBeforeHash 'immediately before native compile'
  $started=[DateTime]::UtcNow
  $record.runtimeAttempted=$true
  $log=@(& $resourceCompiler -i $record.content -game (Join-Path $resourceEngine 'game/dota') -fshallow -nop4 2>&1)
  $compilerExitCode=$LASTEXITCODE
  $record.artifactOwnedHash=Get-ResourceHash $record.artifact
  $log|Set-Content -LiteralPath $record.compilerLog -Encoding UTF8
  Save-ResourceManifest
  if($compilerExitCode -ne 0 -or -not($log -match '\b0 failed\b')){throw "Native compile failed: $($record.relative). See $($record.compilerLog)"}
  if(-not $record.artifactOwnedHash){throw "Native compiler produced no artifact: $($record.relative)"}
  $built=Get-Item -LiteralPath $record.artifact
  if($built.Length -le 0 -or $built.LastWriteTimeUtc -lt $started){throw "Empty or stale artifact: $($record.relative)"}
  Assert-ResourceHash $record.source $record.sourceHash 'after compile'
  Assert-ResourceHash $record.content $record.sourceHash 'after compile'
  $record.compiledHash=$record.artifactOwnedHash
  Save-ResourceManifest
  Write-Output ('DAILY_STARGOLD_NATIVE_COMPILE_PASS '+$record.relative)
 }
 foreach($record in $resourceRecords){
  Assert-ResourceHash $record.source $record.sourceHash 'final source verification'
  Assert-ResourceHash $record.content $record.sourceHash 'final content verification'
  Assert-ResourceHash $record.artifact $record.compiledHash 'final native verification'
 }
 $resourceSucceeded=$true
}catch{
 $resourceFailure=$_.Exception.ToString()
}finally{
 if(-not $resourceSucceeded){
  foreach($record in $resourceRecords){
   foreach($kind in @('content','artifact')){
    $owned=$record.($kind+'OwnedHash')
    if(-not $owned -and -not($kind -eq 'artifact' -and $record.runtimeAttempted)){continue}
    try{
     Assert-ResourceHash $record.$kind $owned "before $kind restore"
     $before=$record.($kind+'BeforeHash')
     if($before){
      $backupPath=if($kind -eq 'artifact'){$record.runtimeBackup}else{$record.contentBackup}
      Assert-ResourceHash $backupPath $before "$kind backup restore"
      Copy-Item -LiteralPath $backupPath -Destination $record.$kind -Force
     }elseif(Test-Path -LiteralPath $record.$kind){
      # Every deletion target was resolved and checked against its fixed root above.
      # No recursion or computed directory deletion is performed.
      Remove-Item -LiteralPath $record.$kind
     }
     Assert-ResourceHash $record.$kind $before "after $kind restore"
     $record.($kind+'Restored')=$true
    }catch{$resourceRestoreErrors+=$_.Exception.Message}
   }
  }
 }
 if(Test-Path -LiteralPath $resourceBackup){Save-ResourceManifest}
}
if($resourceRestoreErrors.Count){throw ($resourceRestoreErrors -join [Environment]::NewLine)}
if($resourceFailure){throw $resourceFailure}
$resourceReport=Join-Path (Split-Path -Parent $resourcePlanFile) 'compile.json'
[pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');success=$true;backup=$resourceBackup;plan=$resourcePlanFile;records=$resourceRecords}|
 ConvertTo-Json -Depth 10|Set-Content -LiteralPath $resourceReport -Encoding UTF8
Write-Output ('DAILY_STARGOLD_NATIVE_COMPILE_ALL_PASS '+$resourceRecords.Count)
