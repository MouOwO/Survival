$ErrorActionPreference='Stop'
$vipRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$vipEngine=[IO.Path]::GetFullPath((Join-Path $vipRepo '../../..'))
$vipContent=Join-Path $vipEngine 'content/dota_addons/Survival/panorama'
$vipCompiler=Join-Path $vipEngine 'game/bin/win64/resourcecompiler.exe'
$vipBackup=Join-Path $vipRepo ('output/shop_vip_tooltip_compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$vipRecords=@()
foreach($relative in @('scripts/custom_game/common/commerce_components.js','styles/custom_game/black_lion_market.css')){
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c'
 $source=Join-Path $vipRepo ('panorama/src/'+$relative)
 $record=[pscustomobject]@{relative=$relative;source=$source;content=(Join-Path $vipContent $relative);artifact=(Join-Path $vipRepo ('panorama/'+$compiled));sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;compiledHash=$null;hadContent=$false;hadArtifact=$false}
 $record.hadContent=Test-Path -LiteralPath $record.content
 $record.hadArtifact=Test-Path -LiteralPath $record.artifact
 foreach($name in @('source','content','runtime')){New-Item -ItemType Directory -Path (Join-Path $vipBackup $name) -Force|Out-Null}
 Copy-Item -LiteralPath $record.source -Destination (Join-Path $vipBackup ('source/'+[IO.Path]::GetFileName($source)))
 if($record.hadContent){Copy-Item -LiteralPath $record.content -Destination (Join-Path $vipBackup ('content/'+[IO.Path]::GetFileName($record.content)))}
 if($record.hadArtifact){Copy-Item -LiteralPath $record.artifact -Destination (Join-Path $vipBackup ('runtime/'+[IO.Path]::GetFileName($record.artifact)))}
 $vipRecords+=$record
}
try{
 foreach($record in $vipRecords){
  Copy-Item -LiteralPath $record.source -Destination $record.content -Force
  $vipStarted=(Get-Date).ToUniversalTime()
  $vipLog=@(& $vipCompiler -i $record.content -game (Join-Path $vipEngine 'game/dota') -fshallow -nop4 2>&1)
  $vipLog|Set-Content -LiteralPath (Join-Path $vipBackup ([IO.Path]::GetFileName($record.source)+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($vipLog -match '0 failed')){throw "VIP tooltip compile failed: $($record.relative)"}
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $vipStarted){throw 'VIP tooltip source drift or stale output'}
  $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
  Write-Output ('VIP_TOOLTIP_COMPILE_PASS '+$record.relative)
 }
}catch{
 foreach($record in $vipRecords){
  if($record.hadContent){Copy-Item -LiteralPath (Join-Path $vipBackup ('content/'+[IO.Path]::GetFileName($record.content))) -Destination $record.content -Force}
  if($record.hadArtifact){Copy-Item -LiteralPath (Join-Path $vipBackup ('runtime/'+[IO.Path]::GetFileName($record.artifact))) -Destination $record.artifact -Force}
 }
 throw
}
$vipReport=Join-Path $vipRepo 'design_refs/shop_catalog_20261016/ui/vip_tooltip_fix/compile.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $vipReport) -Force|Out-Null
@{success=$true;at=(Get-Date -Format o);backup=$vipBackup;records=$vipRecords}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $vipReport -Encoding utf8
