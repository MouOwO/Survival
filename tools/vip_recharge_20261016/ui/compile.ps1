param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$vipRepo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$vipEngine=[IO.Path]::GetFullPath((Join-Path $vipRepo '../../..'))
$vipContent=Join-Path $vipEngine 'content/dota_addons/Survival/panorama'
$vipRuntime=Join-Path $vipRepo 'panorama'
$vipCompiler=Join-Path $vipEngine 'game/bin/win64/resourcecompiler.exe'
$vipFiles=@('scripts/custom_game/common/vip_badges.js','scripts/custom_game/common/archive_tooltip.js','scripts/custom_game/archive_v10.js','scripts/custom_game/vip_window.js','scripts/custom_game/endless_leaderboard.js','styles/custom_game/endless_leaderboard.css','layout/custom_game/archive.xml')
$vipOut=Join-Path $vipRepo 'design_refs/vip_recharge_20261016/ui'
$vipAssembly=Get-Content -LiteralPath (Join-Path $vipOut 'preview/assembly.json') -Raw -Encoding UTF8|ConvertFrom-Json
$vipVisual=Get-Content -LiteralPath (Join-Path $vipOut 'visual_report.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($vipVisual.status -ne 'PASS' -or -not $vipVisual.notGameCapture){throw 'Reviewed isolated-source preview must pass first.'}
$vipBackup=Join-Path $vipRepo ('output/vip_recharge_20261016/ui_compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$records=@()
foreach($relative in $vipFiles){
 $source=[IO.Path]::GetFullPath((Join-Path $vipRepo ('panorama/src/'+$relative)))
 $content=[IO.Path]::GetFullPath((Join-Path $vipContent $relative))
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'
 $artifact=[IO.Path]::GetFullPath((Join-Path $vipRuntime $compiled))
 foreach($pair in @(@($source,(Join-Path $vipRepo 'panorama/src')),@($content,$vipContent),@($artifact,$vipRuntime))){if(-not $pair[0].StartsWith($pair[1]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compile path escaped allowed roots.'}}
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 $preview=@($vipAssembly.sourceGraph|Where-Object {$_.path -eq $relative})
 if($preview.Count -ne 1 -or $preview[0].sha256 -ne $hash){throw "Preview source differs: $relative"}
 $records+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=$hash;contentHash=$null;compiledHash=$null;hadContent=(Test-Path -LiteralPath $content);hadArtifact=(Test-Path -LiteralPath $artifact);contentBackup=(Join-Path $vipBackup ('content/'+$relative));artifactBackup=(Join-Path $vipBackup ('runtime/'+$compiled));verified=$false}
}
if($CheckOnly){Write-Output ('VIP_UI_COMPILE_SCOPE_PASS '+$records.Count);return}
foreach($record in $records){
 foreach($target in @($record.contentBackup,$record.artifactBackup,$record.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
 if($record.hadContent){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
 if($record.hadArtifact){Copy-Item -LiteralPath $record.artifact -Destination $record.artifactBackup}
}
try{
 foreach($record in $records){Copy-Item -LiteralPath $record.source -Destination $record.content -Force}
 foreach($record in $records){
  $start=(Get-Date).ToUniversalTime()
  $log=@(& $vipCompiler -i $record.content -game (Join-Path $vipEngine 'game/dota') -fshallow -nop4 2>&1)
  $exitCode=$LASTEXITCODE
  $log|Set-Content -LiteralPath (Join-Path $vipBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding UTF8
  if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
  if(-not(Test-Path -LiteralPath $record.artifact) -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $start){throw "Missing or stale artifact: $($record.relative)"}
  $record.contentHash=(Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant()
  $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  if($record.contentHash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash){throw 'Sources changed while compiling.'}
  $record.verified=$true
  Write-Output ('VIP_UI_NATIVE_COMPILE_PASS '+$record.relative)
 }
}catch{
 foreach($record in $records){
  if($record.hadContent){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}else{if(Test-Path -LiteralPath $record.content){Remove-Item -LiteralPath $record.content}}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.artifactBackup -Destination $record.artifact -Force}else{if(Test-Path -LiteralPath $record.artifact){Remove-Item -LiteralPath $record.artifact}}
 }
 throw
}
@{at=(Get-Date -Format o);success=$true;notGameCapture=$true;backup=$vipBackup;records=$records}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $vipOut 'compile.json') -Encoding UTF8
