$ErrorActionPreference='Stop'
$redeemRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$redeemEngine=[IO.Path]::GetFullPath((Join-Path $redeemRepo '../../..'))
$redeemContent=Join-Path $redeemEngine 'content/dota_addons/Survival/panorama'
$redeemCompiler=Join-Path $redeemEngine 'game/bin/win64/resourcecompiler.exe'
$redeemBackup=Join-Path $redeemRepo ('output/redemption_codes_20261029/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$redeemSources=@('styles/custom_game/redemption_code.css','layout/custom_game/redemption_code.xml','scripts/custom_game/black_lion_market.js')
$redeemRecords=@()
foreach($relative in $redeemSources){
 $source=Join-Path $redeemRepo ('panorama/src/'+$relative)
 $content=Join-Path $redeemContent $relative
 $runtimeRelative=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'
 $runtime=Join-Path $redeemRepo ('panorama/'+$runtimeRelative)
 $record=[pscustomobject]@{source=$source;content=$content;runtime=$runtime;relative=$relative;sourceHash=(Get-FileHash -LiteralPath $source).Hash;contentExisted=(Test-Path -LiteralPath $content);runtimeExisted=(Test-Path -LiteralPath $runtime);contentBackup=(Join-Path $redeemBackup ('content/'+$relative));runtimeBackup=(Join-Path $redeemBackup ('runtime/'+$runtimeRelative))}
 foreach($target in @($record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null}
 if($record.contentExisted){Copy-Item -LiteralPath $content -Destination $record.contentBackup}
 if($record.runtimeExisted){Copy-Item -LiteralPath $runtime -Destination $record.runtimeBackup}
 $redeemRecords+=$record
}
try {
 foreach($record in $redeemRecords){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.content)|Out-Null
  Copy-Item -LiteralPath $record.source -Destination $record.content -Force
  $started=(Get-Date).ToUniversalTime()
  $log=@(& $redeemCompiler -i $record.content -game (Join-Path $redeemEngine 'game/dota') -fshallow -nop4 2>&1)
  $code=$LASTEXITCODE
  $log|Set-Content -LiteralPath (Join-Path $redeemBackup ((Split-Path -Leaf $record.source)+'.log')) -Encoding utf8
  if($code -ne 0 -or -not($log -match 'OK: [1-9][0-9]* compiled, 0 failed,')){throw 'REDEMPTION_COMPILE_FAILED'}
  if(-not(Test-Path -LiteralPath $record.runtime) -or (Get-Item -LiteralPath $record.runtime).LastWriteTimeUtc -lt $started){throw 'REDEMPTION_OUTPUT_STALE'}
  if((Get-FileHash -LiteralPath $record.content).Hash -ne $record.sourceHash){throw 'REDEMPTION_SOURCE_DRIFT'}
  $record|Add-Member -NotePropertyName compiledHash -NotePropertyValue (Get-FileHash -LiteralPath $record.runtime).Hash
  Write-Output ('REDEMPTION_COMPILED '+$record.relative)
 }
} catch {
 foreach($record in $redeemRecords){
  if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}
  elseif(Test-Path -LiteralPath $record.content){Remove-Item -LiteralPath $record.content}
  if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.runtime -Force}
  elseif(Test-Path -LiteralPath $record.runtime){Remove-Item -LiteralPath $record.runtime}
 }
 throw
}
@{ok=$true;records=$redeemRecords}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $redeemBackup 'result.json') -Encoding utf8
