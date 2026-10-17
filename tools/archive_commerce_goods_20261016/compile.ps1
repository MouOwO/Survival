param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$goodsRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$goodsEngine=[IO.Path]::GetFullPath((Join-Path $goodsRepo '../../..'))
$goodsContent=[IO.Path]::GetFullPath((Join-Path $goodsEngine 'content/dota_addons/Survival/panorama'))
$goodsCompiler=Join-Path $goodsEngine 'game/bin/win64/resourcecompiler.exe'
$goodsFiles=@('scripts/custom_game/archive_v10_semantics.js','scripts/custom_game/common/archive_tooltip.js','scripts/custom_game/archive_v10.js','scripts/custom_game/archive_180de7e38b_titles_compact_v6.js','styles/custom_game/archive_v10.css')
$goodsBackup=Join-Path $goodsRepo ('output/archive_commerce_goods_20261016/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$goodsVisual=Get-Content -LiteralPath (Join-Path $goodsRepo 'design_refs/archive_commerce_goods_20261016/ui/visual_report.json') -Raw -Encoding UTF8|ConvertFrom-Json
$goodsAssembly=Get-Content -LiteralPath (Join-Path $goodsRepo 'design_refs/archive_commerce_goods_20261016/ui/preview/assembly.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($goodsVisual.status -ne 'PASS' -or -not $goodsVisual.notGameCapture){throw 'Reviewed local component validation is required before compilation.'}
$records=@()
foreach($relative in $goodsFiles){
 $source=[IO.Path]::GetFullPath((Join-Path $goodsRepo ('panorama/src/'+$relative)))
 $content=[IO.Path]::GetFullPath((Join-Path $goodsContent $relative))
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c'
 $artifact=[IO.Path]::GetFullPath((Join-Path $goodsRepo ('panorama/'+$compiled)))
 if(-not $source.StartsWith((Join-Path $goodsRepo 'panorama/src')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $content.StartsWith($goodsContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $artifact.StartsWith((Join-Path $goodsRepo 'panorama')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Compile path escaped intended roots: $relative"}
 $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 $preview=@($goodsAssembly.sourceGraph|Where-Object {$_.path -eq $relative})
 if($preview.Count -ne 1 -or $preview[0].sha256 -ne $sourceHash){throw "Reviewed source drift: $relative"}
 $records+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=$sourceHash;compiledHash=$null;hadContent=(Test-Path -LiteralPath $content);hadArtifact=(Test-Path -LiteralPath $artifact);sourceBackup=(Join-Path $goodsBackup ('source/'+$relative));contentBackup=(Join-Path $goodsBackup ('content/'+$relative));runtimeBackup=(Join-Path $goodsBackup ('runtime/'+$compiled))}
}
if($CheckOnly){('ARCHIVE_GOODS_COMPILE_SCOPE_PASS '+$records.Count+' reviewed source files');return}
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
  $log=@(& $goodsCompiler -i $record.content -game (Join-Path $goodsEngine 'game/dota') -fshallow -nop4 2>&1)
  $log|Set-Content -LiteralPath (Join-Path $goodsBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "Compile failed: $($record.relative)"}
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or -not(Test-Path -LiteralPath $record.artifact) -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $start){throw "Source drift or stale artifact: $($record.relative)"}
  $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Output ('ARCHIVE_GOODS_NATIVE_COMPILE_PASS '+$record.relative)
 }
}catch{
 foreach($record in $records){
  if($record.hadContent){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}else{if(Test-Path -LiteralPath $record.content){Remove-Item -LiteralPath $record.content}}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}else{if(Test-Path -LiteralPath $record.artifact){Remove-Item -LiteralPath $record.artifact}}
 }
 throw
}
@{at=(Get-Date -Format o);success=$true;backup=$goodsBackup;notGameCapture=$true;records=$records}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $goodsRepo 'design_refs/archive_commerce_goods_20261016/ui/compile.json') -Encoding utf8
