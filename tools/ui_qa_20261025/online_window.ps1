param(
 [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$GameProcessId,
 [ValidateSet('Capture','Click','ClickOnly','Move','Wheel','Escape','Close')][string]$Action='Capture',
 [ValidatePattern('^[a-z0-9_]{1,60}$')][string]$Label='current',
 [int]$ClickX=-1,[int]$ClickY=-1,
 [switch]$NativeNudge,
 [ValidateRange(-1200,1200)][int]$WheelDelta=-600,
 [ValidateRange(0,5000)][int]$Delay=700
)
# Fixed svt_w24 Tools QA process only. No console, cloud query or credentials.
$ErrorActionPreference='Stop'
if($NativeNudge -and $Action -ne 'Move'){throw 'native_nudge_requires_move'}
$qaRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$qaExpected=[IO.Path]::GetFullPath((Join-Path $qaRoot '../../bin/win64/dota2.exe'))
$qaDetails=Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId"
if(-not $qaDetails -or $qaDetails.ExecutablePath -ine $qaExpected -or
 $qaDetails.CommandLine -notmatch '(?:^|\s)-addon\s+svt_w24(?:\s|$)' -or
 $qaDetails.CommandLine -notmatch '(?:^|\s)-tools(?:\s|$)') {throw 'fixed_online_qa_process_required'}
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class UIQAOnlineWindow {
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
$qaDpi=[UIQAOnlineWindow]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
if($qaDpi -eq [IntPtr]::Zero){throw 'physical_dpi_context_required'}
try {
 $qaWindows=[Collections.Generic.List[long]]::new()
 [void][UIQAOnlineWindow]::EnumWindows({param($w,$unused)
  $owner=[uint32]0;[void][UIQAOnlineWindow]::GetWindowThreadProcessId($w,[ref]$owner)
  $rect=[UIQAOnlineWindow+Rect]::new()
  if($owner -eq $GameProcessId -and [UIQAOnlineWindow]::IsWindowVisible($w) -and
   -not [UIQAOnlineWindow]::IsIconic($w) -and [UIQAOnlineWindow]::GetClientRect($w,[ref]$rect) -and
   ($rect.R-$rect.L) -ge 640 -and ($rect.B-$rect.T) -ge 360){$qaWindows.Add($w.ToInt64())}
  return $true
 },[IntPtr]::Zero)
 if($qaWindows.Count -ne 1){throw 'online_window_ambiguous_or_minimized'}
 $qaHandle=[IntPtr]::new($qaWindows[0])
 if($Action -eq 'Close'){
  [void][UIQAOnlineWindow]::PostMessage($qaHandle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
  Wait-Process -Id $GameProcessId -Timeout 15 -ErrorAction SilentlyContinue
  if(Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue){throw 'owned_game_still_running'}
  @{ok=$true;action='Close';pid=$GameProcessId}|ConvertTo-Json -Compress
  return
 }
 # Use the established foreground-thread handshake; SetForegroundWindow alone
 # is refused by Windows when a newly launched game does not own input yet.
 $qaFocus=& (Join-Path $qaRoot 'tools/focus_live_perf_window.ps1') -GameProcessId $GameProcessId -SkipCursorCenter | ConvertFrom-Json
 if([long]$qaFocus.window -ne $qaHandle.ToInt64()){throw 'online_focus_window_changed'}
 [void][UIQAOnlineWindow]::SetForegroundWindow($qaHandle)
 $qaShell=New-Object -ComObject WScript.Shell
 [void]$qaShell.AppActivate($GameProcessId)
 Start-Sleep -Milliseconds 250
 if([UIQAOnlineWindow]::GetForegroundWindow() -ne $qaHandle){throw 'owned_online_window_not_foreground'}
 $qaRect=[UIQAOnlineWindow+Rect]::new()
 if(-not [UIQAOnlineWindow]::GetClientRect($qaHandle,[ref]$qaRect)){throw 'online_client_rect_missing'}
 if($Action -in @('Click','ClickOnly','Move','Wheel')){
  if($ClickX -lt 0 -or $ClickY -lt 0 -or $ClickX -ge $qaRect.R -or $ClickY -ge $qaRect.B){throw 'online_click_outside_client'}
  $qaPoint=[UIQAOnlineWindow+Point]::new();$qaPoint.X=$ClickX;$qaPoint.Y=$ClickY
  if(-not [UIQAOnlineWindow]::ClientToScreen($qaHandle,[ref]$qaPoint)){throw 'online_client_origin_missing'}
  if([UIQAOnlineWindow]::GetAncestor([UIQAOnlineWindow]::WindowFromPoint($qaPoint),2) -ne $qaHandle){throw 'online_click_covered'}
  if(-not [UIQAOnlineWindow]::SetCursorPos($qaPoint.X,$qaPoint.Y)){throw 'online_pointer_move_failed'}
  if($NativeNudge){
   if($Action -ne 'Move' -or $ClickX+1 -ge $qaRect.R){throw 'native_nudge_requires_interior_move'}
   $qaNext=[UIQAOnlineWindow+Point]::new();$qaNext.X=$qaPoint.X+1;$qaNext.Y=$qaPoint.Y
   if([UIQAOnlineWindow]::GetAncestor([UIQAOnlineWindow]::WindowFromPoint($qaNext),2) -ne $qaHandle){throw 'native_nudge_covered'}
   [UIQAOnlineWindow]::mouse_event(1,1,0,0,[UIntPtr]::Zero)
  }
  # Let the native UI process the pointer move before a distinct click/wheel.
  Start-Sleep -Milliseconds 150
  if($Action -eq 'Wheel'){
   if($WheelDelta -eq 0 -or $WheelDelta % 120 -ne 0){throw 'whole_wheel_notch_required'}
   $qaWheelData=if($WheelDelta -lt 0){[uint32]([int64]4294967296+$WheelDelta)}else{[uint32]$WheelDelta}
   [UIQAOnlineWindow]::mouse_event(0x800,0,0,$qaWheelData,[UIntPtr]::Zero)
  } elseif($Action -ne 'Move'){
   [UIQAOnlineWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
   try {Start-Sleep -Milliseconds 80}finally{[UIQAOnlineWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
  }
 } elseif($Action -eq 'Escape') {
  $qaShell.SendKeys('{ESC}')
 }
 Start-Sleep -Milliseconds $Delay
 if($Action -eq 'ClickOnly'){
  @{ok=$true;action='ClickOnly';pid=$GameProcessId;click=@($ClickX,$ClickY);foreground_changed=([UIQAOnlineWindow]::GetForegroundWindow() -ne $qaHandle);screenshot=$null}|ConvertTo-Json -Compress
  return
 }
 if([UIQAOnlineWindow]::GetForegroundWindow() -ne $qaHandle){throw 'online_window_lost_foreground_before_capture'}
 $qaOrigin=[UIQAOnlineWindow+Point]::new()
 if(-not [UIQAOnlineWindow]::ClientToScreen($qaHandle,[ref]$qaOrigin)){throw 'online_client_origin_missing'}
 Add-Type -AssemblyName System.Drawing
 $qaOut=Join-Path $qaRoot 'output/ui_qa_20261025/online'
 [void][IO.Directory]::CreateDirectory($qaOut)
 $qaTarget=Join-Path $qaOut ($Label+'.png')
 if(Test-Path -LiteralPath $qaTarget){throw 'online_capture_already_exists'}
 $qaBitmap=[Drawing.Bitmap]::new($qaRect.R,$qaRect.B)
 $qaGraphics=[Drawing.Graphics]::FromImage($qaBitmap)
 try {
  $qaGraphics.CopyFromScreen($qaOrigin.X,$qaOrigin.Y,0,0,$qaBitmap.Size)
  if([UIQAOnlineWindow]::GetForegroundWindow() -ne $qaHandle){throw 'online_window_lost_foreground_during_capture'}
  $qaBitmap.Save($qaTarget,[Drawing.Imaging.ImageFormat]::Png)
 } finally {$qaGraphics.Dispose();$qaBitmap.Dispose()}
 $qaRecord=@{ok=$true;action=$Action;pid=$GameProcessId;at_utc=[DateTime]::UtcNow.ToString('o');width=$qaRect.R;height=$qaRect.B;screenshot=$qaTarget;click=@($ClickX,$ClickY);native_pointer_nudge=[bool]$NativeNudge;wheel_delta=$(if($Action -eq 'Wheel'){$WheelDelta}else{0});scope='fixed_online_tools_ui_only';visual_review='pending'}
 $qaRecord|ConvertTo-Json -Depth 4|Set-Content -LiteralPath ($qaTarget+'.json') -Encoding UTF8
 $qaRecord|ConvertTo-Json -Depth 4 -Compress
} finally {[void][UIQAOnlineWindow]::SetThreadDpiAwarenessContext($qaDpi)}
