param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$marketRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$marketEngine=[IO.Path]::GetFullPath((Join-Path $marketRepo '../../..'))
$marketContent=Join-Path $marketEngine 'content/dota_addons/Survival/panorama'
$marketCompiler=Join-Path $marketEngine 'game/bin/win64/resourcecompiler.exe'
$marketFiles=@('scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','scripts/custom_game/lottery_gw2.js','scripts/custom_game/commerce_wallet.js','scripts/custom_game/remaining_5d5c1152eb.js')
$marketBackup=Join-Path $marketRepo ('output/commerce_points_20261016/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$records=@()
foreach($relative in $marketFiles){
 $source=Join-Path $marketRepo ('panorama/src/'+$relative)
 if(-not(Test-Path -LiteralPath $source)){throw "Missing source $relative"}
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'
 $content=Join-Path $marketContent $relative
 $artifact=Join-Path $marketRepo ('panorama/'+$compiled)
 $records+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;compiledHash=$null;hadContent=(Test-Path -LiteralPath $content);hadArtifact=(Test-Path -LiteralPath $artifact);sourceBackup=(Join-Path $marketBackup ('source/'+$relative));contentBackup=(Join-Path $marketBackup ('content/'+$relative));runtimeBackup=(Join-Path $marketBackup ('runtime/'+$compiled))}
}
if($CheckOnly){('COMMERCE_POINTS_COMPILE_SCOPE_PASS '+$marketFiles.Count+' source files');return}
foreach($record in $records){
 foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup,$record.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
 Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
 if($record.hadContent){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
 if($record.hadArtifact){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
try{
 foreach($record in $records){
  Copy-Item -LiteralPath $record.source -Destination $record.content -Force
  $start=(Get-Date).ToUniversalTime()
  $log=@(& $marketCompiler -i $record.content -game (Join-Path $marketEngine 'game/dota') -fshallow -nop4 2>&1)
  $log|Set-Content -LiteralPath (Join-Path $marketBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "Compile failed: $($record.relative)"}
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash -or -not(Test-Path -LiteralPath $record.artifact) -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $start){throw "Source drift or stale compile: $($record.relative)"}
  $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
  Write-Output ('COMMERCE_POINTS_COMPILE_PASS '+$record.relative)
 }
}catch{
 foreach($record in $records){
  if($record.hadContent){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}else{if(Test-Path -LiteralPath $record.content){Remove-Item -LiteralPath $record.content}}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}else{if(Test-Path -LiteralPath $record.artifact){Remove-Item -LiteralPath $record.artifact}}
 }
 throw
}
$report=Join-Path $marketRepo 'design_refs/commerce_points_20261016/compile.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $report) -Force|Out-Null
@{at=(Get-Date -Format o);success=$true;backup=$marketBackup;records=$records}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $report -Encoding utf8
