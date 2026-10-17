param([Parameter(Mandatory=$true)][int]$GameProcessId,[switch]$SkipCursorCenter)
$ErrorActionPreference='Stop'
$process=Get-Process -Id $GameProcessId
if($process.ProcessName -ne 'dota2'){throw 'Not the requested test game'}
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class LivePerfFocusV2 {
 public delegate bool EnumWindowsProc(IntPtr window,IntPtr argument);
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 public class WindowInfo {
  public long Hwnd; public uint Pid; public string Title;
  public bool Visible,Iconic,ClientRectValid; public int ClientWidth,ClientHeight;
 }
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback,IntPtr argument);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window,StringBuilder title,int capacity);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out Rect rect);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool attach);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window,int state);
 [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr window);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window,ref Point point);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
 public static WindowInfo[] FindWindows(uint requestedPid) {
  var result=new List<WindowInfo>();
  EnumWindowsProc callback=(window,argument)=>{
   uint pid;GetWindowThreadProcessId(window,out pid);if(pid!=requestedPid)return true;
   var title=new StringBuilder(512);GetWindowText(window,title,title.Capacity);
   Rect rect;bool rectValid=GetClientRect(window,out rect);
   result.Add(new WindowInfo {Hwnd=window.ToInt64(),Pid=pid,Title=title.ToString(),
    Visible=IsWindowVisible(window),Iconic=IsIconic(window),ClientRectValid=rectValid,
    ClientWidth=rectValid?rect.Right-rect.Left:0,ClientHeight=rectValid?rect.Bottom-rect.Top:0});
   return true;
  };
  if(!EnumWindows(callback,IntPtr.Zero))throw new InvalidOperationException("EnumWindows failed");
  return result.ToArray();
 }
}
'@
function Find-GameWindow {
 $windows=@([LivePerfFocusV2]::FindWindows([uint32]$GameProcessId))
 $candidates=@($windows | Where-Object {$_.Title -ceq 'Dota 2' -and $_.Visible -and $_.ClientRectValid -and $_.ClientWidth -ge 640 -and $_.ClientHeight -ge 360})
 if($candidates.Count -ne 1){
  $diagnostic=$windows | Select-Object Hwnd,Title,Visible,Iconic,ClientRectValid,ClientWidth,ClientHeight | ConvertTo-Json -Compress
  throw "Expected one real Dota 2 window; found $($candidates.Count). Requested PID windows: $diagnostic"
 }
 return $candidates[0]
}
$selected=Find-GameWindow
$window=[IntPtr]$selected.Hwnd
$oldForeground=[LivePerfFocusV2]::GetForegroundWindow()
[uint32]$foregroundProcess=0
$foregroundThread=[LivePerfFocusV2]::GetWindowThreadProcessId($oldForeground,[ref]$foregroundProcess)
$thisThread=[LivePerfFocusV2]::GetCurrentThreadId()
$shell=New-Object -ComObject WScript.Shell
[void]$shell.AppActivate($GameProcessId)
$attached=$false
try {
 if($foregroundThread -ne 0 -and $foregroundThread -ne $thisThread){$attached=[LivePerfFocusV2]::AttachThreadInput($thisThread,$foregroundThread,$true)}
 [void][LivePerfFocusV2]::ShowWindow($window,9)
 [void][LivePerfFocusV2]::BringWindowToTop($window)
 [void][LivePerfFocusV2]::SetForegroundWindow($window)
} finally {if($attached){[void][LivePerfFocusV2]::AttachThreadInput($thisThread,$foregroundThread,$false)}}
Start-Sleep -Milliseconds 500
$verified=Find-GameWindow
if($verified.Hwnd -ne $selected.Hwnd){throw 'Real game window changed during focus restoration'}
$activeHandle=[LivePerfFocusV2]::GetForegroundWindow()
$active=$activeHandle -eq $window -and -not $verified.Iconic
if(-not $active){throw 'Real Dota 2 window did not retain foreground; no valid capture'}
$center=New-Object LivePerfFocusV2+Point
$center.X=[int][Math]::Floor($verified.ClientWidth / 2)
$center.Y=[int][Math]::Floor($verified.ClientHeight / 2)
if(-not [LivePerfFocusV2]::ClientToScreen($window,[ref]$center)){throw 'Real client center could not be mapped to screen'}
if(-not $SkipCursorCenter -and -not [LivePerfFocusV2]::SetCursorPos($center.X,$center.Y)){throw 'Cursor could not be centered in the real game client'}
$cursor=New-Object LivePerfFocusV2+Point
$cursorRead=[LivePerfFocusV2]::GetCursorPos([ref]$cursor)
$cursorCentered=$cursorRead -and $cursor.X -eq $center.X -and $cursor.Y -eq $center.Y
[pscustomobject]@{pid=$GameProcessId;foreground=$active;target_hwnd=$window.ToInt64();window=$window.ToInt64();
 foreground_handle=$activeHandle.ToInt64();title=$verified.Title;client_width=$verified.ClientWidth;client_height=$verified.ClientHeight;
 visible=$verified.Visible;iconic=$verified.Iconic;selection_unique=$true;client_rect_valid=$verified.ClientRectValid;
 cursor_centered=$cursorCentered;cursor_centering_skipped=[bool]$SkipCursorCenter;cursor_screen_x=$cursor.X;cursor_screen_y=$cursor.Y} | ConvertTo-Json -Compress
if(-not $SkipCursorCenter -and -not $cursorCentered){throw 'Cursor did not retain the verified real client center'}
