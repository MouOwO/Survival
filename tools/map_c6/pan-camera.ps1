param([ValidateRange(1,120)][int]$Seconds=26)
$ErrorActionPreference='Stop'
# Native edge-pan input for an explicitly prepared survival performance capture.
# Never focus another application; abort as soon as the user changes focus.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SurvivalPerfPan {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref Point p);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 public struct Rect {public int Left,Top,Right,Bottom;}
 public struct Point {public int X,Y;}
}
'@
$panWindow=[SurvivalPerfPan]::GetForegroundWindow()
$panPid=0
[void][SurvivalPerfPan]::GetWindowThreadProcessId($panWindow,[ref]$panPid)
$panProcess=Get-CimInstance Win32_Process -Filter "ProcessId=$panPid"
if(-not $panProcess -or $panProcess.Name -ne 'dota2.exe' -or $panProcess.CommandLine -notmatch '-addon\s+survival(?:\s|$)'){
 throw 'Foreground is not the explicitly launched survival Tools game'
}
$panRect=[SurvivalPerfPan+Rect]::new()
[void][SurvivalPerfPan]::GetClientRect($panWindow,[ref]$panRect)
if($panRect.Right -lt 640 -or $panRect.Bottom -lt 480){throw 'Game client is not visible'}
$panOrigin=[SurvivalPerfPan+Point]::new()
[void][SurvivalPerfPan]::ClientToScreen($panWindow,[ref]$panOrigin)
$panClock=[Diagnostics.Stopwatch]::StartNew()
$panMoves=0;$panLastSide=-1
try {
 while($panClock.Elapsed.TotalSeconds -lt $Seconds){
  if([SurvivalPerfPan]::GetForegroundWindow() -ne $panWindow){throw 'Focus changed; stopped test camera input'}
  $panSide=[int][Math]::Floor(($panClock.Elapsed.TotalSeconds+0.325)/0.65)%2
  if($panSide -ne $panLastSide){
   $panX=if($panSide -eq 0){2}else{$panRect.Right-3}
   [void][SurvivalPerfPan]::SetCursorPos($panOrigin.X+$panX,$panOrigin.Y+[int]($panRect.Bottom/2))
   $panLastSide=$panSide;$panMoves++
  }
  [Threading.Thread]::Sleep(50)
 }
 Write-Output "EXTREME_NATIVE_CAMERA_PAN completed=1 duration=$($panClock.Elapsed.TotalSeconds) edge_changes=$panMoves"
} finally {
 if([SurvivalPerfPan]::GetForegroundWindow() -eq $panWindow){
  [void][SurvivalPerfPan]::SetCursorPos($panOrigin.X+[int]($panRect.Right/2),$panOrigin.Y+[int]($panRect.Bottom/2))
 }
}
