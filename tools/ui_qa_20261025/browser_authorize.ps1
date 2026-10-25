param(
 [Parameter(Mandatory=$true)][int]$BrowserProcessId,
 [ValidateSet('Capture','Click')][string]$Action='Capture',
 [ValidatePattern('^[a-z0-9_]{1,50}$')][string]$Label='authorization',
 [int]$ClickX=-1,[int]$ClickY=-1
)
# Only the visibly opened WS4/Steam authorization tab. No cookies, hidden form
# values, browser profile files, clipboard, password input or HTTP replay.
$ErrorActionPreference='Stop'
$qaBrowser=Get-Process -Id $BrowserProcessId
$qaDetails=Get-CimInstance Win32_Process -Filter "ProcessId=$BrowserProcessId"
if($qaBrowser.ProcessName -ne 'chrome' -or $qaDetails.ExecutablePath -ine 'C:\Program Files\Google\Chrome\Application\chrome.exe') {throw 'expected_chrome_process_required'}
if($qaBrowser.MainWindowTitle -notmatch '^(WS4 |\u6388\u6743\u5b8c\u6210|Steam \u793e\u533a|Steam Community|Sign In|\u767b\u5f55)' -and $qaBrowser.MainWindowTitle -notmatch '^(?:https?://)?pay\.xiaofengnet\.com/ws4-web/steam/login(?:\?|$)') {throw 'authorization_tab_required'}
$qaHandle=$qaBrowser.MainWindowHandle
if($qaHandle -eq 0){throw 'browser_window_missing'}
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class UIQAAuthWindow {
 [StructLayout(LayoutKind.Sequential)]public struct Rect {public int L,T,R,B;}
 [StructLayout(LayoutKind.Sequential)]public struct Point {public int X,Y;}
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll")]public static extern bool GetClientRect(IntPtr w,out Rect r);
 [DllImport("user32.dll")]public static extern bool ClientToScreen(IntPtr w,ref Point p);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr w,out uint p);
 [DllImport("kernel32.dll")]public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")]public static extern bool AttachThreadInput(uint a,uint b,bool attach);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr w,int s);
 [DllImport("user32.dll")]public static extern bool BringWindowToTop(IntPtr w);
 [DllImport("user32.dll")]public static extern IntPtr WindowFromPoint(Point p);
 [DllImport("user32.dll")]public static extern IntPtr GetAncestor(IntPtr w,uint f);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
}
'@
$qaDpi=[UIQAAuthWindow]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
if($qaDpi -eq [IntPtr]::Zero){throw 'physical_dpi_context_required'}
try {
 $qaForeground=[UIQAAuthWindow]::GetForegroundWindow()
 $qaForegroundOwner=[uint32]0
 $qaForegroundThread=[UIQAAuthWindow]::GetWindowThreadProcessId($qaForeground,[ref]$qaForegroundOwner)
 $qaThread=[UIQAAuthWindow]::GetCurrentThreadId()
 $qaShell=New-Object -ComObject WScript.Shell
 [void]$qaShell.AppActivate($BrowserProcessId)
 $qaAttached=$false
 try{
  if($qaForegroundThread -ne 0 -and $qaForegroundThread -ne $qaThread){$qaAttached=[UIQAAuthWindow]::AttachThreadInput($qaThread,$qaForegroundThread,$true)}
  [void][UIQAAuthWindow]::ShowWindow($qaHandle,9)
  [void][UIQAAuthWindow]::BringWindowToTop($qaHandle)
  [void][UIQAAuthWindow]::SetForegroundWindow($qaHandle)
 }finally{if($qaAttached){[void][UIQAAuthWindow]::AttachThreadInput($qaThread,$qaForegroundThread,$false)}}
 Start-Sleep -Milliseconds 250
 if([UIQAAuthWindow]::GetForegroundWindow() -ne $qaHandle){throw 'authorization_window_not_foreground'}
 $qaRect=[UIQAAuthWindow+Rect]::new()
 if(-not [UIQAAuthWindow]::GetClientRect($qaHandle,[ref]$qaRect)){throw 'browser_client_rect_missing'}
 if($Action -eq 'Click'){
  if($ClickX -lt 0 -or $ClickY -lt 100 -or $ClickX -ge $qaRect.R -or $ClickY -ge $qaRect.B){throw 'authorization_click_outside_page'}
  $qaPoint=[UIQAAuthWindow+Point]::new();$qaPoint.X=$ClickX;$qaPoint.Y=$ClickY
  if(-not [UIQAAuthWindow]::ClientToScreen($qaHandle,[ref]$qaPoint)){throw 'browser_origin_missing'}
  if([UIQAAuthWindow]::GetAncestor([UIQAAuthWindow]::WindowFromPoint($qaPoint),2) -ne $qaHandle){throw 'authorization_click_covered'}
  if(-not [UIQAAuthWindow]::SetCursorPos($qaPoint.X,$qaPoint.Y)){throw 'browser_pointer_move_failed'}
  [UIQAAuthWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
  try{Start-Sleep -Milliseconds 80}finally{[UIQAAuthWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
  Start-Sleep -Milliseconds 1200
 }
 $qaBrowser.Refresh()
 if($qaBrowser.MainWindowTitle -notmatch '^(WS4 |\u6388\u6743\u5b8c\u6210|Steam \u793e\u533a|Steam Community|Sign In|\u767b\u5f55)' -and $qaBrowser.MainWindowTitle -notmatch '^(?:https?://)?pay\.xiaofengnet\.com/ws4-web/steam/login(?:\?|$)') {throw 'authorization_navigation_in_progress_or_other_tab'}
 if([UIQAAuthWindow]::GetForegroundWindow() -ne $qaHandle){throw 'authorization_window_lost_foreground'}
 $qaOrigin=[UIQAAuthWindow+Point]::new()
 if(-not [UIQAAuthWindow]::ClientToScreen($qaHandle,[ref]$qaOrigin)){throw 'browser_origin_missing'}
 $qaRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
 $qaOut=Join-Path $qaRoot 'output/ui_qa_20261025/online'
 [void][IO.Directory]::CreateDirectory($qaOut)
 $qaTarget=Join-Path $qaOut ('browser_'+$Label+'.png')
 if(Test-Path -LiteralPath $qaTarget){throw 'authorization_capture_exists'}
 Add-Type -AssemblyName System.Drawing
 # Omit tabs/address bar: OpenID callback URLs and unrelated tab titles are
 # unnecessary evidence. Click coordinates remain relative to the full client.
 $qaBitmap=[Drawing.Bitmap]::new($qaRect.R,($qaRect.B-100))
 $qaGraphics=[Drawing.Graphics]::FromImage($qaBitmap)
 try{
  $qaGraphics.CopyFromScreen($qaOrigin.X,($qaOrigin.Y+100),0,0,$qaBitmap.Size)
  if([UIQAAuthWindow]::GetForegroundWindow() -ne $qaHandle){throw 'authorization_focus_changed_during_capture'}
  $qaBitmap.Save($qaTarget,[Drawing.Imaging.ImageFormat]::Png)
 }finally{$qaGraphics.Dispose();$qaBitmap.Dispose()}
 @{ok=$true;action=$Action;pid=$BrowserProcessId;screenshot=$qaTarget;crop_top=100;width=$qaRect.R;full_client_height=$qaRect.B;at_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress
}finally{[void][UIQAAuthWindow]::SetThreadDpiAwarenessContext($qaDpi)}
