param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$emeraldRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$emeraldEngine=[IO.Path]::GetFullPath((Join-Path $emeraldRepo '../../..'))
$emeraldContent=Join-Path $emeraldEngine 'content/dota_addons/Survival/panorama'
$emeraldOutput=Join-Path $emeraldRepo 'output/lottery_emerald_buttons_20261019'
$emeraldPlan=Get-Content -LiteralPath (Join-Path $emeraldOutput 'compile_plan.json') -Raw -Encoding UTF8|ConvertFrom-Json
$emeraldExpected=@('scripts/custom_game/lottery_gw2.js','styles/custom_game/lottery_gw2.css')
if(($emeraldPlan.files.path -join '|') -cne ($emeraldExpected -join '|')){throw 'Only the two reviewed emerald presentation sources may be compiled.'}
$emeraldBackup=Join-Path $emeraldOutput ('compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$emeraldRecords=@()
foreach($entry in $emeraldPlan.files){
 $relative=[string]$entry.path
 $source=Join-Path $emeraldRepo ('panorama/src/'+$relative)
 $content=Join-Path $emeraldContent $relative
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c'
 $artifact=Join-Path $emeraldRepo ('panorama/'+$compiled)
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 if($hash -cne $entry.sha256){throw "Reviewed source drift: $relative"}
 $emeraldRecords+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sha256=$hash;runtimeSha256=$null;hadContent=(Test-Path -LiteralPath $content);hadArtifact=(Test-Path -LiteralPath $artifact);sourceBackup=(Join-Path $emeraldBackup ('source/'+$relative));contentBackup=(Join-Path $emeraldBackup ('content/'+$relative));runtimeBackup=(Join-Path $emeraldBackup ('runtime/'+$compiled))}
}
if($CheckOnly){Write-Output 'EMERALD_COMPILE_SCOPE_PASS 2';return}
$env:TEMP=Join-Path $emeraldOutput 'compiler_tmp';$env:TMP=$env:TEMP
New-Item -ItemType Directory -Path $env:TEMP -Force|Out-Null
foreach($record in $emeraldRecords){
 foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup,$record.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
 Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
 if($record.hadContent){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
 if($record.hadArtifact){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
try{
 foreach($record in $emeraldRecords){Copy-Item -LiteralPath $record.source -Destination $record.content -Force}
 foreach($record in $emeraldRecords){
  $start=[DateTime]::UtcNow
  $log=@(& (Join-Path $emeraldEngine 'game/bin/win64/resourcecompiler.exe') -i $record.content -game (Join-Path $emeraldEngine 'game/dota') -fshallow -nop4 2>&1)
  $log|Set-Content -LiteralPath (Join-Path $emeraldBackup ((Split-Path -Leaf $record.source)+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "Compile failed: $($record.relative)"}
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256 -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256 -or -not(Test-Path -LiteralPath $record.artifact) -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $start){throw "Source drift or stale runtime: $($record.relative)"}
  $record.runtimeSha256=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Output ('EMERALD_NATIVE_COMPILE_PASS '+$record.relative)
 }
 foreach($record in $emeraldRecords){
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256 -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256 -or (Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.runtimeSha256){throw "Source/content/runtime drift: $($record.relative)"}
 }
}catch{
 foreach($record in $emeraldRecords){
  if($record.hadContent){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content){Remove-Item -LiteralPath $record.content}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}elseif(Test-Path -LiteralPath $record.artifact){Remove-Item -LiteralPath $record.artifact}
 }
 throw
}
@{at=[DateTime]::UtcNow.ToString('o');success=$true;backup=$emeraldBackup;records=$emeraldRecords}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $emeraldOutput 'compile.json') -Encoding utf8
