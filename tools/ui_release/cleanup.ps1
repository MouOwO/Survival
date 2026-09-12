$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$plan=Get-Content (Join-Path $PSScriptRoot 'plan.json') -Raw | ConvertFrom-Json
if(-not(Test-Path (Join-Path $PSScriptRoot 'compiled.json'))){throw 'Formal compile must pass before cleanup'}
$receipt=Get-Content (Join-Path $PSScriptRoot 'backup_verified.json') -Raw | ConvertFrom-Json
if(-not $receipt.crc_verified -or -not(Test-Path -LiteralPath $receipt.archive)){throw 'Verified backup missing'}
$records=Get-Content (Join-Path $plan.backup_root 'manifest.json') -Raw | ConvertFrom-Json
$map=@{};foreach($r in $records){$map[$r.path]=$r.sha256}
$allowed=@((Join-Path $repo 'spikes'),(Join-Path $repo 'panorama'),(Join-Path $engine 'content/dota_addons/Survival/panorama'))
$deleted=@();$skipped=@();$freed=0L
foreach($entry in $plan.cleanup){
 $target=[IO.Path]::GetFullPath($entry)
 $valid=$false;foreach($root in $allowed){if($target.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$valid=$true}}
 if(-not $valid){throw "Unsafe cleanup path: $target"}
 if(-not(Test-Path -LiteralPath $target)){continue}
 $item=Get-Item -LiteralPath $target -Force
 $files=if($item.PSIsContainer){@(Get-ChildItem -LiteralPath $target -Recurse -File -Force)}else{@($item)}
 $size=0L
 foreach($f in $files){
  if(-not $map.ContainsKey($f.FullName) -or (Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant() -ne $map[$f.FullName]){throw "Not backed up or changed since backup: $($f.FullName)"}
  $size+=$f.Length
 }
 try{Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop;$deleted+=$target;$freed+=$size}catch{$skipped+=@{path=$target;reason=$_.Exception.Message}}
}
@{deleted=$deleted;skipped=$skipped;bytes=$freed;backup=$receipt.archive} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PSScriptRoot 'cleanup_result.json') -Encoding utf8
"CLEANUP_DONE targets=$($deleted.Count) skipped=$($skipped.Count) MB=$([Math]::Round($freed/1MB))"
