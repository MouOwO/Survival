param(
 [Parameter(Mandatory=$true)][string]$ReceiptPath,
 [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$GameProcessId,
 [ValidateSet('CheckOnly','Capture','Click','ClickOnly','Move','Wheel','Escape','Close')][string]$Action='CheckOnly',
 [ValidatePattern('^[a-z0-9_]{1,60}$')][string]$Label='current',
 [int]$ClickX=-1,[int]$ClickY=-1,
 [ValidateRange(-1200,1200)][int]$WheelDelta=-600,
 [ValidateRange(0,5000)][int]$Delay=700
)
# The default only checks this new ordinary Workshop receipt/PID/vcon owner.
# Explicit physical GUI actions never send console commands or read tokens.
$ErrorActionPreference='Stop'
$qaRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$qaPython='D:/Survival_安全工具/venv/Scripts/python.exe'
$qaGuardPath=Join-Path $PSScriptRoot 'launch_workshop.py'
$qaGuardRaw=& $qaPython -B -X utf8 $qaGuardPath --check-receipt $ReceiptPath --pid $GameProcessId
if($LASTEXITCODE -ne 0){throw 'ordinary_workshop_receipt_guard_rejected'}
$qaGuard=$qaGuardRaw|ConvertFrom-Json
if(-not $qaGuard.ok -or [int]$qaGuard.pid -ne $GameProcessId -or [int]$qaGuard.port -ne 29007 -or
 $qaGuard.workshop_id -cne '3824360109'){throw 'ordinary_workshop_receipt_guard_rejected'}
if($Action -eq 'CheckOnly'){$qaGuard|ConvertTo-Json -Depth 4 -Compress;return}
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class UIQAWorkshopWindow {
 public delegate bool EnumProc(IntPtr window,IntPtr data);
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int L,T,R,B;}
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr data);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr w,out uint p);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr w);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr w);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr w,out Rect r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr w,ref Point p);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr w,uint flags);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr w,uint m,IntPtr wp,IntPtr lp);
}
'@
$qaDpi=[UIQAWorkshopWindow]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
if($qaDpi -eq [IntPtr]::Zero){throw 'physical_dpi_context_required'}
try {
 $qaWindows=[Collections.Generic.List[long]]::new()
 [void][UIQAWorkshopWindow]::EnumWindows({param($w,$unused)
  $owner=[uint32]0;[void][UIQAWorkshopWindow]::GetWindowThreadProcessId($w,[ref]$owner)
  $rect=[UIQAWorkshopWindow+Rect]::new()
  if($owner -eq $GameProcessId -and [UIQAWorkshopWindow]::IsWindowVisible($w) -and
   -not [UIQAWorkshopWindow]::IsIconic($w) -and [UIQAWorkshopWindow]::GetClientRect($w,[ref]$rect) -and
   ($rect.R-$rect.L) -ge 640 -and ($rect.B-$rect.T) -ge 360){$qaWindows.Add($w.ToInt64())}
  return $true
 },[IntPtr]::Zero)
 if($qaWindows.Count -ne 1){throw 'online_window_ambiguous_or_minimized'}
 $qaHandle=[IntPtr]::new($qaWindows[0])
 if($Action -eq 'Close'){
  [void][UIQAWorkshopWindow]::PostMessage($qaHandle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
  Wait-Process -Id $GameProcessId -Timeout 15 -ErrorAction SilentlyContinue
  if(Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue){throw 'owned_game_still_running'}
  @{ok=$true;action='Close';pid=$GameProcessId}|ConvertTo-Json -Compress
  return
 }
 # Use the established foreground-thread handshake; SetForegroundWindow alone
 # is refused by Windows when a newly launched game does not own input yet.
 $qaFocus=& (Join-Path $qaRoot 'tools/focus_live_perf_window.ps1') -GameProcessId $GameProcessId -SkipCursorCenter | ConvertFrom-Json
 if([long]$qaFocus.window -ne $qaHandle.ToInt64()){throw 'online_focus_window_changed'}
 [void][UIQAWorkshopWindow]::SetForegroundWindow($qaHandle)
 $qaShell=New-Object -ComObject WScript.Shell
 [void]$qaShell.AppActivate($GameProcessId)
 Start-Sleep -Milliseconds 250
 if([UIQAWorkshopWindow]::GetForegroundWindow() -ne $qaHandle){throw 'owned_online_window_not_foreground'}
 $qaRect=[UIQAWorkshopWindow+Rect]::new()
 if(-not [UIQAWorkshopWindow]::GetClientRect($qaHandle,[ref]$qaRect)){throw 'online_client_rect_missing'}
 if($Action -in @('Click','ClickOnly','Move','Wheel')){
  if($ClickX -lt 0 -or $ClickY -lt 0 -or $ClickX -ge $qaRect.R -or $ClickY -ge $qaRect.B){throw 'online_click_outside_client'}
  $qaPoint=[UIQAWorkshopWindow+Point]::new();$qaPoint.X=$ClickX;$qaPoint.Y=$ClickY
  if(-not [UIQAWorkshopWindow]::ClientToScreen($qaHandle,[ref]$qaPoint)){throw 'online_client_origin_missing'}
  if([UIQAWorkshopWindow]::GetAncestor([UIQAWorkshopWindow]::WindowFromPoint($qaPoint),2) -ne $qaHandle){throw 'online_click_covered'}
  if(-not [UIQAWorkshopWindow]::SetCursorPos($qaPoint.X,$qaPoint.Y)){throw 'online_pointer_move_failed'}
  # Let the native UI process the pointer move before a distinct click/wheel.
  Start-Sleep -Milliseconds 150
  if($Action -eq 'Wheel'){
   if($WheelDelta -eq 0 -or $WheelDelta % 120 -ne 0){throw 'whole_wheel_notch_required'}
   $qaWheelData=if($WheelDelta -lt 0){[uint32]([int64]4294967296+$WheelDelta)}else{[uint32]$WheelDelta}
   [UIQAWorkshopWindow]::mouse_event(0x800,0,0,$qaWheelData,[UIntPtr]::Zero)
  } elseif($Action -ne 'Move'){
   [UIQAWorkshopWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
   try {Start-Sleep -Milliseconds 80}finally{[UIQAWorkshopWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
  }
 } elseif($Action -eq 'Escape') {
  $qaShell.SendKeys('{ESC}')
 }
 Start-Sleep -Milliseconds $Delay
 if($Action -eq 'ClickOnly'){
  @{ok=$true;action='ClickOnly';pid=$GameProcessId;click=@($ClickX,$ClickY);foreground_changed=([UIQAWorkshopWindow]::GetForegroundWindow() -ne $qaHandle);screenshot=$null}|ConvertTo-Json -Compress
  return
 }
 if([UIQAWorkshopWindow]::GetForegroundWindow() -ne $qaHandle){throw 'online_window_lost_foreground_before_capture'}
 $qaOrigin=[UIQAWorkshopWindow+Point]::new()
 if(-not [UIQAWorkshopWindow]::ClientToScreen($qaHandle,[ref]$qaOrigin)){throw 'online_client_origin_missing'}
 Add-Type -AssemblyName System.Drawing
 $qaOut=[IO.Path]::GetFullPath([string]$qaGuard.capture_directory)
 if((Test-Path -LiteralPath $qaOut) -and ((Get-Item -LiteralPath $qaOut).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'workshop_capture_reparse_forbidden'}
 [void][IO.Directory]::CreateDirectory($qaOut)
 $qaTarget=Join-Path $qaOut ($Label+'.png')
 if(Test-Path -LiteralPath $qaTarget){throw 'online_capture_already_exists'}
 $qaBitmap=[Drawing.Bitmap]::new($qaRect.R,$qaRect.B)
 $qaGraphics=[Drawing.Graphics]::FromImage($qaBitmap)
 try {
  $qaGraphics.CopyFromScreen($qaOrigin.X,$qaOrigin.Y,0,0,$qaBitmap.Size)
  if([UIQAWorkshopWindow]::GetForegroundWindow() -ne $qaHandle){throw 'online_window_lost_foreground_during_capture'}
  $qaImageStream=[IO.File]::Open($qaTarget,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {$qaBitmap.Save($qaImageStream,[Drawing.Imaging.ImageFormat]::Png)}finally{$qaImageStream.Dispose()}
 } finally {$qaGraphics.Dispose();$qaBitmap.Dispose()}
 $qaRecord=@{ok=$true;action=$Action;pid=$GameProcessId;at_utc=[DateTime]::UtcNow.ToString('o');width=$qaRect.R;height=$qaRect.B;screenshot=$qaTarget;click=@($ClickX,$ClickY);wheel_delta=$(if($Action -eq 'Wheel'){$WheelDelta}else{0});scope='fixed_ordinary_original_workshop_physical_GUI_only';launch_receipt=[IO.Path]::GetFullPath($ReceiptPath);visual_review='pending'}
 $qaMetadataStream=[IO.StreamWriter]::new([IO.File]::Open(($qaTarget+'.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None),[Text.UTF8Encoding]::new($false))
 try{$qaMetadataStream.WriteLine(($qaRecord|ConvertTo-Json -Depth 4))}finally{$qaMetadataStream.Dispose()}
 $qaRecord|ConvertTo-Json -Depth 4 -Compress
} finally {[void][UIQAWorkshopWindow]::SetThreadDpiAwarenessContext($qaDpi)}
