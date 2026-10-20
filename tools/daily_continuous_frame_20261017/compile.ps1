param([string]$Plan='design_refs/daily_continuous_frame_20261017/compile_plan.json',[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$resourceRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resourceEngine=[IO.Path]::GetFullPath((Join-Path $resourceRepo '../../..'))
$resourceContent=[IO.Path]::GetFullPath((Join-Path $resourceEngine 'content/dota_addons/Survival/panorama'))
$resourceCompiler=Join-Path $resourceEngine 'game/bin/win64/resourcecompiler.exe'
$resourcePlanFile=[IO.Path]::GetFullPath((Join-Path $resourceRepo $Plan))
if(-not $resourcePlanFile.StartsWith((Join-Path $resourceRepo 'design_refs/daily_continuous_frame_20261017')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compile plan is outside this task output directory.'}
$resourcePlan=Get-Content -LiteralPath $resourcePlanFile -Raw -Encoding UTF8|ConvertFrom-Json
$resourceBackup=Join-Path $resourceRepo ('output/daily_continuous_frame_20261017/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$records=@()
foreach($entry in $resourcePlan.files){
 $relative=[string]$entry.path
 if($relative -notmatch '^(scripts|styles|layout)/[A-Za-z0-9_./-]+\.(js|css|xml)$' -or $relative.Contains('..')){throw "Unexpected compilation source: $relative"}
 $source=[IO.Path]::GetFullPath((Join-Path $resourceRepo ('panorama/src/'+$relative)))
 $content=[IO.Path]::GetFullPath((Join-Path $resourceContent $relative))
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'
 $artifact=[IO.Path]::GetFullPath((Join-Path $resourceRepo ('panorama/'+$compiled)))
 foreach($pair in @(@($source,(Join-Path $resourceRepo 'panorama/src')),@($content,$resourceContent),@($artifact,(Join-Path $resourceRepo 'panorama')))){
  if(-not $pair[0].StartsWith($pair[1]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Compile path escaped intended root: $relative"}
 }
 $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 if($entry.sha256 -ne $sourceHash){throw "Reviewed source drift: $relative"}
 $records+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=$sourceHash;compiledHash=$null;hadContent=(Test-Path -LiteralPath $content);hadArtifact=(Test-Path -LiteralPath $artifact);sourceBackup=(Join-Path $resourceBackup ('source/'+$relative));contentBackup=(Join-Path $resourceBackup ('content/'+$relative));runtimeBackup=(Join-Path $resourceBackup ('runtime/'+$compiled))}
}
if(-not $records.Count){throw 'Compile plan is empty.'}
if($CheckOnly){('DAILY_CONTINUOUS_FRAME_COMPILE_SCOPE_PASS '+$records.Count+' reviewed source files');return}
foreach($record in $records){
 foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup,$record.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
 Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
 if($record.hadContent){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
 if($record.hadArtifact){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
try{
 foreach($record in $records){Copy-Item -LiteralPath $record.source -Destination $record.content -Force}
 foreach($record in $records){
  $start=(Get-Date).ToUniversalTime()
  $log=@(& $resourceCompiler -i $record.content -game (Join-Path $resourceEngine 'game/dota') -fshallow -nop4 2>&1)
  $log|Set-Content -LiteralPath (Join-Path $resourceBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "Compile failed: $($record.relative)"}
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or -not(Test-Path -LiteralPath $record.artifact) -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $start){throw "Source drift or stale compile: $($record.relative)"}
  $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Output ('DAILY_CONTINUOUS_FRAME_NATIVE_COMPILE_PASS '+$record.relative)
 }
 foreach($record in $records){
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.compiledHash){throw "Source/content/runtime changed during the batch: $($record.relative)"}
 }
}catch{
 foreach($record in $records){
  if($record.hadContent){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content){Remove-Item -LiteralPath $record.content}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}elseif(Test-Path -LiteralPath $record.artifact){Remove-Item -LiteralPath $record.artifact}
 }
 throw
}
@{at=(Get-Date -Format o);success=$true;backup=$resourceBackup;plan=$resourcePlanFile;records=$records}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $resourceRepo 'design_refs/daily_continuous_frame_20261017/compile.json') -Encoding utf8
