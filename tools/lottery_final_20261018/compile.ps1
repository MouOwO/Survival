param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$lotteryRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lotteryEngine=[IO.Path]::GetFullPath((Join-Path $lotteryRepo '../../..'))
$lotteryContent=Join-Path $lotteryEngine 'content/dota_addons/Survival/panorama'
$lotteryCompiler=Join-Path $lotteryEngine 'game/bin/win64/resourcecompiler.exe'
$lotteryPlan=Get-Content -LiteralPath (Join-Path $lotteryRepo 'output/lottery_final_20261018/compile_plan.json') -Raw -Encoding utf8 | ConvertFrom-Json
$lotteryBackup=Join-Path $lotteryRepo ('output/lottery_final_20261018/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$lotteryRecords=@()
foreach($lotteryEntry in $lotteryPlan.files){
 $lotteryRelative=[string]$lotteryEntry.path
 if($lotteryRelative -notmatch '^(scripts/custom_game/lottery_gw2\.js|styles/custom_game/lottery_gw2\.css|layout/custom_game/lottery_gw2_assets\.xml|images/custom_game/lottery_final_v1/[a-z0-9_]+\.(png|svg))$'){throw 'Unexpected source in lottery final compile plan'}
 $lotterySource=Join-Path $lotteryRepo ('panorama/src/'+$lotteryRelative)
 $lotteryDestination=[IO.Path]::GetFullPath((Join-Path $lotteryContent $lotteryRelative))
 $lotteryCompiled=$lotteryRelative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c' -replace '\.svg$','.vsvg_c'
 $lotteryArtifact=[IO.Path]::GetFullPath((Join-Path $lotteryRepo ('panorama/'+$lotteryCompiled)))
 if(-not $lotteryDestination.StartsWith($lotteryContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $lotteryArtifact.StartsWith((Join-Path $lotteryRepo 'panorama')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compile target escaped intended roots'}
 if((Get-FileHash -LiteralPath $lotterySource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lotteryEntry.sha256){throw ('Reviewed source changed: '+$lotteryRelative)}
 $lotteryHadContent=Test-Path -LiteralPath $lotteryDestination
 $lotteryHadArtifact=Test-Path -LiteralPath $lotteryArtifact
 $lotteryReusable=$lotteryHadContent -and $lotteryHadArtifact -and ((Get-FileHash -LiteralPath $lotteryDestination -Algorithm SHA256).Hash.ToLowerInvariant() -eq $lotteryEntry.sha256)
 $lotteryBeforeHash=if($lotteryHadArtifact){(Get-FileHash -LiteralPath $lotteryArtifact -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null}
 $lotteryRecords+=[pscustomobject]@{relative=$lotteryRelative;source=$lotterySource;sourceHash=$lotteryEntry.sha256;content=$lotteryDestination;artifact=$lotteryArtifact;isImage=($lotteryRelative -match '^images/');hadContent=$lotteryHadContent;hadArtifact=$lotteryHadArtifact;reuseImage=$lotteryReusable;artifactHashBefore=$lotteryBeforeHash;contentBackup=(Join-Path $lotteryBackup ('content/'+$lotteryRelative));runtimeBackup=(Join-Path $lotteryBackup ('runtime/'+$lotteryCompiled));compiledHash=$null}
}
if($lotteryRecords.Count -ne 23){throw 'Expected exactly three runtime sources and twenty new decoration/mask images'}
if($CheckOnly){Write-Output ('LOTTERY_FINAL_COMPILE_SCOPE_PASS '+$lotteryRecords.Count);return}
foreach($lotteryRecord in $lotteryRecords){
 foreach($lotteryTarget in @($lotteryRecord.contentBackup,$lotteryRecord.runtimeBackup,$lotteryRecord.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $lotteryTarget) -Force | Out-Null}
 if($lotteryRecord.hadContent){Copy-Item -LiteralPath $lotteryRecord.content -Destination $lotteryRecord.contentBackup}
 if($lotteryRecord.hadArtifact){Copy-Item -LiteralPath $lotteryRecord.artifact -Destination $lotteryRecord.runtimeBackup}
}
try{
 foreach($lotteryRecord in $lotteryRecords){Copy-Item -LiteralPath $lotteryRecord.source -Destination $lotteryRecord.content -Force}
 $lotteryStart=(Get-Date).ToUniversalTime()
 foreach($lotteryRecord in @($lotteryRecords | Where-Object {-not $_.isImage} | Sort-Object @{Expression={if($_.relative -like 'layout/*'){1}else{0}}},relative)){
  $lotteryLog=@(& $lotteryCompiler -i $lotteryRecord.content -game (Join-Path $lotteryEngine 'game/dota') -fshallow -nop4 2>&1)
  $lotteryLog | Set-Content -LiteralPath (Join-Path $lotteryBackup (([IO.Path]::GetFileName($lotteryRecord.source))+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($lotteryLog -match '0 failed')){throw ('Native compile failed: '+$lotteryRecord.relative)}
  Write-Output ('LOTTERY_FINAL_COMPILE_PASS '+$lotteryRecord.relative)
 }
 foreach($lotteryRecord in $lotteryRecords){
  if((Get-FileHash -LiteralPath $lotteryRecord.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lotteryRecord.sourceHash -or (Get-FileHash -LiteralPath $lotteryRecord.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lotteryRecord.sourceHash){throw 'Source/content drift during compilation'}
  $lotteryCompiledFile=Get-Item -LiteralPath $lotteryRecord.artifact
  $lotteryRecord.compiledHash=(Get-FileHash -LiteralPath $lotteryRecord.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  $lotteryUnchangedImage=$lotteryRecord.isImage -and $lotteryRecord.reuseImage -and $lotteryRecord.compiledHash -eq $lotteryRecord.artifactHashBefore
  if($lotteryCompiledFile.Length -le 0 -or ($lotteryCompiledFile.LastWriteTimeUtc -lt $lotteryStart -and -not $lotteryUnchangedImage)){throw ('Compiled resource missing or stale: '+$lotteryRecord.relative)}
 }
}catch{
 foreach($lotteryRecord in $lotteryRecords){
  if($lotteryRecord.hadContent){Copy-Item -LiteralPath $lotteryRecord.contentBackup -Destination $lotteryRecord.content -Force}elseif(Test-Path -LiteralPath $lotteryRecord.content){Remove-Item -LiteralPath $lotteryRecord.content}
  if($lotteryRecord.hadArtifact){Copy-Item -LiteralPath $lotteryRecord.runtimeBackup -Destination $lotteryRecord.artifact -Force}elseif(Test-Path -LiteralPath $lotteryRecord.artifact){Remove-Item -LiteralPath $lotteryRecord.artifact}
 }
 throw
}
@{at=(Get-Date -Format o);success=$true;records=$lotteryRecords;backup=$lotteryBackup} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $lotteryRepo 'output/lottery_final_20261018/compile.json') -Encoding utf8
