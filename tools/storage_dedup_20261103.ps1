param([switch]$Apply,[ValidateSet('round1','round2')][string]$Round='round1')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath('D:\Survival_发布候选')
$names = @('20261021_noncommercial_preflight_01','20261021_secure_release_01','20261022_four_accounts_v01','20261022_four_accounts_v02','20261023_ws4_auth_v01')
if ($Round -eq 'round2') { $names = @('20261021_noncommercial_preflight_01','20261023_ws4_auth_v02','20261023_ws4_auth_v03','20261024_ws4_web_auth_v01') }
$reportRoot = Join-Path $PSScriptRoot '..\output\storage_dedup_20261103'
[void](New-Item -ItemType Directory -Path $reportRoot -Force)
$planPath = Join-Path $reportRoot 'expanded_plan.json'
$receiptPath = Join-Path $reportRoot 'expanded_receipt.json'
if ($Round -eq 'round2') { $planPath=Join-Path $reportRoot 'expanded_plan_round2.json'; $receiptPath=Join-Path $reportRoot 'expanded_receipt_round2.json' }
function Check-File([string]$path) {
 $absolute = [IO.Path]::GetFullPath($path)
 if (-not $absolute.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'outside_explicit_candidate_root' }
 $relative = $absolute.Substring($root.Length+1)
 $parts = $relative.Split('\')
 if ($parts.Length -lt 3 -or $names -notcontains $parts[0] -or $parts[1] -eq 'maps') { throw 'outside_allowlisted_old_art' }
 if ($absolute -notmatch '\.(vtex_c|vmdl_c|otf|webm|vpcf_c|vsnd_c|vmat_c)$') { throw 'not_an_immutable_art_resource' }
 $check = $absolute
 while ($check.Length -ge $root.Length) {
  $item = Get-Item -LiteralPath $check -Force
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'reparse_point_rejected' }
  if ($check -eq $root) { break }
  $check = Split-Path -Parent $check
 }
 return Get-Item -LiteralPath $absolute -Force
}
function Digest([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
if (-not $Apply) {
 if (Test-Path -LiteralPath $planPath) { throw 'plan_already_exists' }
 $canonical = @{}; $operations = @(); $hashed = 0
 foreach ($name in $names) {
  $dir = Join-Path $root $name
  if ((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'candidate_reparse_point' }
  foreach ($file in (Get-ChildItem -LiteralPath $dir -File -Recurse)) {
   if ($file.Length -lt 1048576) { continue }
   $relative = $file.FullName.Substring($dir.Length+1)
   if ($relative.StartsWith('maps\') -or $relative -notmatch '\.(vtex_c|vmdl_c|otf|webm|vpcf_c|vsnd_c|vmat_c)$') { continue }
   [void](Check-File $file.FullName)
   $key = $relative+'|'+$file.Length
   if (-not $canonical.ContainsKey($key)) { $canonical[$key] = @{path=$file.FullName; hash=$null}; continue }
   if ($file.LinkType -eq 'HardLink') { continue }
   $source = $canonical[$key]
   if (-not $source.hash) { $source.hash = Digest $source.path; $hashed++ }
   $hash = Digest $file.FullName; $hashed++
   if ($hash -eq $source.hash) { $operations += [pscustomobject]@{source=$source.path;target=$file.FullName;bytes=$file.Length;sha256=$hash} }
  }
 }
 $plan = [ordered]@{schema=1;kind='EXACT_OLD_IMMUTABLE_ART_DEDUP';root=$root;allowlist=$names;operations=$operations;duplicate_bytes=($operations | Measure-Object bytes -Sum).Sum;free_before=(Get-PSDrive D).Free;hash_calls=$hashed;maps_and_vpk_excluded=$true;signature_and_manifest_excluded=$true}
 $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
 [pscustomobject]@{status='READ_ONLY_EXPANDED_PLAN';operations=$operations.Count;duplicate_bytes=$plan.duplicate_bytes;hash_calls=$hashed} | ConvertTo-Json
 exit
}
if (Test-Path -LiteralPath $receiptPath) { throw 'receipt_already_exists_do_not_replay' }
$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($plan.root -ne $root -or ($plan.allowlist -join '|') -ne ($names -join '|')) { throw 'plan_scope_changed' }
$completed = @(); $freed = 0
foreach ($op in $plan.operations) {
 $source = Check-File $op.source; $target = Check-File $op.target
 if ($target.LinkType -eq 'HardLink') { throw 'target_changed_since_plan' }
 if ($source.Length -ne $op.bytes -or $target.Length -ne $op.bytes -or (Digest $source.FullName) -ne $op.sha256 -or (Digest $target.FullName) -ne $op.sha256) { throw 'resource_changed_since_plan' }
 $temp = $target.FullName + '.dedup-link-' + [guid]::NewGuid().ToString('N')
 $backup = $target.FullName + '.dedup-original-' + [guid]::NewGuid().ToString('N')
 if ((Test-Path -LiteralPath $temp) -or (Test-Path -LiteralPath $backup)) { throw 'temporary_path_exists' }
 [void](New-Item -ItemType HardLink -Path $temp -Target $source.FullName)
 [IO.File]::Replace($temp,$target.FullName,$backup)
 if ((Digest $target.FullName) -ne $op.sha256 -or (Digest $backup) -ne $op.sha256) { throw 'post_replace_hash_mismatch_original_preserved' }
 $backupAbsolute = [IO.Path]::GetFullPath($backup)
 if (-not $backupAbsolute.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Parent $backupAbsolute) -ne (Split-Path -Parent $target.FullName)) { throw 'backup_delete_scope_invalid' }
 Remove-Item -LiteralPath $backupAbsolute -Force
 $completed += $op; $freed += $op.bytes
 [ordered]@{schema=1;completed=$completed;free_before=$plan.free_before;free_after=(Get-PSDrive D).Free;immutable_hardlinks_do_not_edit_in_place=$true;package_paths_and_bytes_preserved=$true;current_install_or_backup_modified=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
 if ($completed.Count % 100 -eq 0) { Write-Output ('VERIFIED_RESOURCES '+$completed.Count) }
 if ($freed -ge 12000000000) { break }
}
[pscustomobject]@{status='OLD_DUPLICATE_STORAGE_REMOVED';operations=$completed.Count;free_now=(Get-PSDrive D).Free;freed_bytes=((Get-PSDrive D).Free-$plan.free_before)} | ConvertTo-Json
