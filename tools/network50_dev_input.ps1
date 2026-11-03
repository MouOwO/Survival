param(
 [Parameter(Mandatory=$true)][ValidateSet('Focus','Click','Screenshot','SelectBuilder','CancelTarget')][string]$Action,
 [ValidateSet('run02','run03','run04','run05','run06','run07')][string]$Run='run02',
 [int]$X=-1,[int]$Y=-1,
 [ValidatePattern('^[a-z0-9_-]{1,60}$')][string]$Name='screen'
)
# One explicit UI operation on the already-owned Tools process. No launch,
# arbitrary keys, console text, script injection, messages or focus retry.
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$receiptPath=Join-Path ('D:/Survival_本地排演/network50_dev_20261103/'+$Run) 'process.json'
$receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
$prepared=Get-Content -LiteralPath (Join-Path (Split-Path $receiptPath) 'prepared.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($receipt.status -ne 'ACTUAL_PROJECT_TOOLS_OFFLINE_STARTED' -or $receipt.production_acceptance -ne $false -or
 $receipt.snapshot_manifest_sha256 -ne $prepared.manifest_sha256){throw 'owned_tools_snapshot_receipt_required'}
$gameProcess=[int]$receipt.pid
if($gameProcess -lt 1 -or -not $receipt.created){throw 'immutable_process_identity_required'}
$created=if($receipt.created -is [DateTime]){$receipt.created.ToUniversalTime()}
 elseif($receipt.created -is [DateTimeOffset]){$receipt.created.UtcDateTime}
 else{[DateTimeOffset]::Parse([string]$receipt.created).UtcDateTime}
$expectedExe=[IO.Path]::GetFullPath((Join-Path $repo '../../bin/win64/dota2.exe'))
function Assert-DevProcess {
 $detail=Get-CimInstance Win32_Process -Filter "ProcessId=$gameProcess"
 if(-not $detail -or $detail.Name -ne 'dota2.exe' -or -not $detail.ExecutablePath -or
  [IO.Path]::GetFullPath($detail.ExecutablePath) -ne $expectedExe -or
  $detail.CommandLine -notmatch '(?:^|\s)-tools(?:\s|$)' -or
  $detail.CommandLine -notmatch '(?:^|\s)-addon\s+(?:"svt_network50_dev"|svt_network50_dev)(?:\s|$)' -or
  ([regex]::Matches($detail.CommandLine,'(?:^|\s)-addon(?:\s|$)')).Count -ne 1 -or
  $null -eq $detail.CreationDate -or [Math]::Abs(($detail.CreationDate.ToUniversalTime()-$created).TotalMilliseconds) -gt 1){
  throw 'owned_tools_alias_process_identity_changed'
 }
}
Assert-DevProcess
if(-not ('ArcadeInput' -as [type])){
 # Reuse the reviewed native window/input type, never execute the old helper
 # (that helper deliberately admits ordinary clients and has a wider CLI).
 $legacy=[IO.File]::ReadAllText((Join-Path $repo 'tools/arcade_portrait_perf_20261031/input_arcade.ps1'))
 $match=[regex]::Match($legacy,"(?s)Add-Type @'\r?\n(.*?)\r?\n'@")
 if(-not $match.Success){throw 'reviewed_native_input_type_missing'}
 Add-Type -TypeDefinition $match.Groups[1].Value
}
Add-Type -AssemblyName System.Drawing
$priorDpi=[ArcadeInput]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
if($priorDpi -eq [IntPtr]::Zero){throw 'physical_dpi_context_unavailable'}
try{
 $window=[ArcadeInput]::FindMain([uint32]$gameProcess)
 $bounds=[ArcadeInput+R]::new()
 if(-not [ArcadeInput]::GetClientRect($window,[ref]$bounds)){throw 'client_bounds_unavailable'}
 $width=$bounds.Rt-$bounds.L;$height=$bounds.B-$bounds.T
 $before=[ArcadeInput]::EventsInserted
 $path=$null
 if($Action -eq 'Focus'){
  [ArcadeInput]::RequireUniqueFocusTitle($window)
  $shell=New-Object -ComObject WScript.Shell
  try{$accepted=[bool]$shell.AppActivate('Dota 2')}
  finally{if([Runtime.InteropServices.Marshal]::IsComObject($shell)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}}
  Start-Sleep -Milliseconds 150
  Assert-DevProcess
  [ArcadeInput]::EnsureForeground($window,[uint32]$gameProcess)
  if(-not $accepted){throw 'explicit_focus_not_accepted'}
 }elseif($Action -eq 'Click'){
  Assert-DevProcess
  [ArcadeInput]::EnsureForeground($window,[uint32]$gameProcess)
  if($X -lt 0 -or $Y -lt 0 -or $X -ge $width -or $Y -ge $height){throw 'point_outside_client'}
  $point=[ArcadeInput+P]::new();$point.X=$X;$point.Y=$Y
  if(-not [ArcadeInput]::ClientToScreen($window,[ref]$point) -or
   [ArcadeInput]::GetAncestor([ArcadeInput]::WindowFromPoint($point),2) -ne $window){throw 'point_occluded'}
  if(-not [ArcadeInput]::SetCursorPos($point.X,$point.Y)){throw 'cursor_move_failed'}
  Assert-DevProcess
  [ArcadeInput]::EnsureForeground($window,[uint32]$gameProcess)
  [ArcadeInput]::MouseEvent($false)
  try{Start-Sleep -Milliseconds 60}finally{[ArcadeInput]::MouseEvent($true)}
 }elseif($Action -eq 'SelectBuilder' -or $Action -eq 'CancelTarget'){
  Assert-DevProcess
  [ArcadeInput]::EnsureForeground($window,[uint32]$gameProcess)
  $fixedKey=if($Action -eq 'SelectBuilder'){0x71}else{0x1B}
  try{
   [ArcadeInput]::KeyEvent([uint16]$fixedKey,$false)
   Start-Sleep -Milliseconds 60
  }finally{[ArcadeInput]::KeyEvent([uint16]$fixedKey,$true)}
 }else{
  Assert-DevProcess
  [ArcadeInput]::EnsureForeground($window,[uint32]$gameProcess)
  $point=[ArcadeInput+P]::new()
  if(-not [ArcadeInput]::ClientToScreen($window,[ref]$point)){throw 'client_screen_origin_unavailable'}
  $folder=Join-Path $repo ('output/network50_dev_20261103/'+$Run)
  [void][IO.Directory]::CreateDirectory($folder)
  $leaf=$Name+'_'+[DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8)+'.png'
  $path=Join-Path $folder $leaf
  $bitmap=New-Object System.Drawing.Bitmap($width,$height)
  $graphics=[Drawing.Graphics]::FromImage($bitmap)
  $stream=$null
  try{
   $graphics.CopyFromScreen($point.X,$point.Y,0,0,$bitmap.Size,[Drawing.CopyPixelOperation]::SourceCopy)
   Assert-DevProcess
   [ArcadeInput]::EnsureForeground($window,[uint32]$gameProcess)
   $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
  }finally{if($stream){$stream.Dispose()};$graphics.Dispose();$bitmap.Dispose()}
 }
 Assert-DevProcess
 [ArcadeInput]::EnsureForeground($window,[uint32]$gameProcess)
 [ordered]@{status='OWNED_TOOLS_ACTION_COMPLETED';run=$Run;pid=$gameProcess;created=$receipt.created;action=$Action;
  client_width=$width;client_height=$height;x=$X;y=$Y;path=$path;events_inserted=([ArcadeInput]::EventsInserted-$before);
  focus_attempts=$(if($Action -eq 'Focus'){1}else{0});automatic_retry=$false;script_injection=$false;account_operations=0}|ConvertTo-Json -Compress
}finally{[void][ArcadeInput]::SetThreadDpiAwarenessContext($priorDpi)}
