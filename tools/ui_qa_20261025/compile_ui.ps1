[CmdletBinding()]
param([switch]$CheckOnly,[switch]$UiFontWallet,[switch]$UiStackable)
$ErrorActionPreference='Stop'
$qaRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$qaEngine=[IO.Path]::GetFullPath((Join-Path $qaRepo '../../..'))
$qaContent=[IO.Path]::GetFullPath((Join-Path $qaEngine 'content/dota_addons/Survival'))
$qaCompiler=Join-Path $qaEngine 'game/bin/win64/resourcecompiler.exe'
$qaScope=@('scripts/custom_game/topnav_remaining_5d5c1152eb.js','scripts/custom_game/ui_layers.js',
 'scripts/custom_game/common/ui_components.js','scripts/custom_game/payment_test.js','scripts/custom_game/commerce_wallet.js')
if($UiFontWallet){
 $qaScope=@('scripts/custom_game/common/archive_font_v36.js','scripts/custom_game/daily_remaining_5d5c1152eb.js','scripts/custom_game/commerce_wallet.js')
}
if($UiStackable){
 if($UiFontWallet){throw 'Choose one compile scope'}
 $qaScope=@('scripts/custom_game/archive_v10_semantics.js','scripts/custom_game/archive_v10.js','scripts/custom_game/common/archive_tooltip.js')
}
$qaStamp=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$qaOutput=Join-Path $qaRepo ('output/ui_qa_20261025/compile/'+$qaStamp)
$qaPlan=@()
foreach($relative in $qaScope){
 $source=Join-Path $qaRepo ('panorama/src/'+$relative)
 $destination=Join-Path $qaContent ('panorama/'+$relative)
 $runtime=Join-Path $qaRepo ('panorama/'+[IO.Path]::ChangeExtension($relative,'vjs_c'))
 if(-not [IO.File]::Exists($source) -or -not [IO.File]::Exists($destination) -or -not [IO.File]::Exists($runtime)){throw 'Scoped source/content/runtime missing'}
 $qaPlan+=@{relative=$relative;source=$source;destination=$destination;runtime=$runtime;source_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()}
}
if($CheckOnly){@{ok=$true;check_only=$true;scope=$qaScope;source_count=$qaPlan.Count}|ConvertTo-Json -Depth 5;exit 0}
[void][IO.Directory]::CreateDirectory($qaOutput)
$qaResults=@()
foreach($item in $qaPlan){
 $backup=Join-Path $qaOutput ('before/'+$item.relative)
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup))
 [IO.File]::Copy($item.destination,$backup,$false)
 [IO.File]::Copy($item.runtime,[IO.Path]::ChangeExtension($backup,'vjs_c'),$false)
 if((Get-FileHash -LiteralPath $item.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.source_sha256){throw 'Source changed before compile'}
 [IO.File]::Copy($item.source,$item.destination,$true)
 $log=Join-Path $qaOutput (($item.relative -replace '[/\\]','_')+'.log')
 & $qaCompiler -i $item.destination -fshallow -nop4 *> $log
 if($LASTEXITCODE -ne 0){throw ('Scoped compile failed: '+$item.relative)}
 if((Get-FileHash -LiteralPath $item.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.source_sha256){throw 'Source changed during compile'}
 if((Get-FileHash -LiteralPath $item.destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.source_sha256){throw 'Content mirror differs'}
 $qaResults+=@{relative=$item.relative;source_sha256=$item.source_sha256;content_sha256=(Get-FileHash -LiteralPath $item.destination -Algorithm SHA256).Hash.ToLowerInvariant();runtime_sha256=(Get-FileHash -LiteralPath $item.runtime -Algorithm SHA256).Hash.ToLowerInvariant();runtime_bytes=(Get-Item -LiteralPath $item.runtime).Length;log=$log}
}
$qaReport=@{ok=$true;check_only=$false;at_utc=[DateTimeOffset]::UtcNow.ToString('o');scope=$qaScope;results=$qaResults;compiled_files=$qaResults.Count;output=$qaOutput}
$qaReport|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $qaOutput 'compile.json') -Encoding UTF8
@{ok=$true;compiled_files=$qaResults.Count;output=$qaOutput}|ConvertTo-Json -Depth 4
