$ErrorActionPreference='Stop'
$plan=Get-Content tools/art_assets/content_cleanup_plan.json -Raw | ConvertFrom-Json
$root=[IO.Path]::GetFullPath($plan.content)
$expected='D:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\Survival'
if($root -ne $expected){throw 'Unexpected content root'}
$backup='D:\survival_ui_backups\content_cleanup_20260912'
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$records=@()
foreach($entry in $plan.remove){
 $target=[IO.Path]::GetFullPath((Join-Path $root $entry.relative))
 if(-not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Outside content root'}
 $item=Get-Item -LiteralPath $target
 if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected link'}
 $files=if($item.PSIsContainer){@(Get-ChildItem -LiteralPath $target -Recurse -File)}else{@($item)}
 foreach($f in $files){
  $rel=$f.FullName.Substring($root.Length+1);$dest=Join-Path $backup $rel
  New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
  Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
  $hash=(Get-FileHash -LiteralPath $f.FullName).Hash
  if($hash -ne (Get-FileHash -LiteralPath $dest).Hash){throw 'Backup mismatch'}
  $records+=@{relative=$rel;sha256=$hash;bytes=$f.Length}
 }
}
foreach($entry in $plan.remove){
 $target=[IO.Path]::GetFullPath((Join-Path $root $entry.relative))
 if(-not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe deletion'}
 Remove-Item -LiteralPath $target -Recurse -Force
}
@{backup=$backup;files=$records;count=$records.Count;bytes=($records | Measure-Object bytes -Sum).Sum} | ConvertTo-Json -Depth 5 | Set-Content tools/art_assets/content_cleanup_result.json -Encoding UTF8
Write-Output "Backed up and removed $($records.Count) files."
