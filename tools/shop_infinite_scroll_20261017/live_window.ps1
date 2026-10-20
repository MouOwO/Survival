param([int]$GameProcessId=19756,[int]$ClickX=-1,[int]$ClickY=-1,[int]$WheelX=-1,[int]$WheelY=-1,[int]$WheelDelta=-120,[ValidateRange(1,200)][int]$WheelSteps=1,[string]$Screenshot)
$ErrorActionPreference='Stop'
$clarityRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$clarityInfo=& (Join-Path $clarityRepo 'tools/focus_live_perf_window.ps1') -GameProcessId $GameProcessId -SkipCursorCenter | ConvertFrom-Json
Start-Sleep -Milliseconds 500
Add-Type @'
using System;using System.Runtime.InteropServices;
public class CollectionClarityInput {
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [StructLayout(LayoutKind.Sequential)] public struct Mouse {public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Explicit)] public struct Union {[FieldOffset(0)]public Mouse Mouse;}
 [StructLayout(LayoutKind.Sequential)] public struct Input {public uint Type;public Union Value;}
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern bool ClientToScreen(IntPtr w,ref Point p);
 [DllImport("user32.dll")]public static extern IntPtr WindowFromPoint(Point p);
 [DllImport("user32.dll")]public static extern IntPtr GetAncestor(IntPtr w,uint flags);
 [DllImport("user32.dll")]public static extern int GetSystemMetrics(int i);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr v);
 [DllImport("user32.dll")]public static extern uint SendInput(uint n,Input[] a,int size);
 public static void Click(int x,int y){
  int vx=GetSystemMetrics(76),vy=GetSystemMetrics(77),vw=GetSystemMetrics(78),vh=GetSystemMetrics(79);
  var move=new Input{Type=0,Value=new Union{Mouse=new Mouse{X=(int)Math.Round((x-vx)*65535.0/(vw-1)),Y=(int)Math.Round((y-vy)*65535.0/(vh-1)),Flags=0xc001}}};
  var down=new Input{Type=0,Value=new Union{Mouse=new Mouse{Flags=2}}};var up=new Input{Type=0,Value=new Union{Mouse=new Mouse{Flags=4}}};
  if(SendInput(3,new Input[]{move,down,up},Marshal.SizeOf(typeof(Input)))!=3)throw new Exception("Input delivery failed");
 }
 public static void Wheel(int x,int y,int delta){
  int vx=GetSystemMetrics(76),vy=GetSystemMetrics(77),vw=GetSystemMetrics(78),vh=GetSystemMetrics(79);
  var move=new Input{Type=0,Value=new Union{Mouse=new Mouse{X=(int)Math.Round((x-vx)*65535.0/(vw-1)),Y=(int)Math.Round((y-vy)*65535.0/(vh-1)),Flags=0xc001}}};
  var wheel=new Input{Type=0,Value=new Union{Mouse=new Mouse{Data=unchecked((uint)delta),Flags=0x800}}};
  if(SendInput(2,new Input[]{move,wheel},Marshal.SizeOf(typeof(Input)))!=2)throw new Exception("Wheel delivery failed");
 }
}
'@
$clarityWindow=[IntPtr]::new([long]$clarityInfo.window)
$clarityInputSent=$false
$clarityDpi=[CollectionClarityInput]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
try{
 if([CollectionClarityInput]::GetForegroundWindow() -ne $clarityWindow){throw 'Verified game lost foreground.'}
 if(($ClickX -ge 0) -ne ($ClickY -ge 0)){throw 'Both client coordinates required.'}
 if($ClickX -ge 0){
  if($ClickX -ge $clarityInfo.client_width -or $ClickY -ge $clarityInfo.client_height){throw 'Click outside verified client.'}
  $clarityPoint=[CollectionClarityInput+Point]::new();$clarityPoint.X=$ClickX;$clarityPoint.Y=$ClickY
  if(-not[CollectionClarityInput]::ClientToScreen($clarityWindow,[ref]$clarityPoint)){throw 'Client origin missing.'}
  if([CollectionClarityInput]::GetAncestor([CollectionClarityInput]::WindowFromPoint($clarityPoint),2) -ne $clarityWindow){throw 'Target covered by another window.'}
  [CollectionClarityInput]::Click($clarityPoint.X,$clarityPoint.Y)
  $clarityInputSent=$true
  Start-Sleep -Milliseconds 700
 }
 if(($WheelX -ge 0) -ne ($WheelY -ge 0)){throw 'Both wheel coordinates required.'}
 if($WheelX -ge 0){
  if($WheelX -ge $clarityInfo.client_width -or $WheelY -ge $clarityInfo.client_height){throw 'Wheel outside verified client.'}
  $wheelPoint=[CollectionClarityInput+Point]::new();$wheelPoint.X=$WheelX;$wheelPoint.Y=$WheelY
  if(-not[CollectionClarityInput]::ClientToScreen($clarityWindow,[ref]$wheelPoint)){throw 'Wheel client origin missing.'}
  for($wheelIndex=0;$wheelIndex -lt $WheelSteps;$wheelIndex++){
   if([CollectionClarityInput]::GetForegroundWindow() -ne $clarityWindow){throw 'Verified game lost foreground before wheel.'}
   if([CollectionClarityInput]::GetAncestor([CollectionClarityInput]::WindowFromPoint($wheelPoint),2) -ne $clarityWindow){throw 'Wheel target covered by another window.'}
   [CollectionClarityInput]::Wheel($wheelPoint.X,$wheelPoint.Y,$WheelDelta)
   Start-Sleep -Milliseconds 80
  }
  Start-Sleep -Milliseconds 800
 }
 if($Screenshot){
  $clarityCapture=& (Join-Path $clarityRepo 'tools/menus_v10/window.ps1') -ProcessId $GameProcessId -Screenshot $Screenshot -CaptureDelayMs 500 | ConvertFrom-Json
  $clarityCapture|Add-Member -NotePropertyName VerifiedCollectionInputSent -NotePropertyValue $clarityInputSent
  $clarityCapture|Add-Member -NotePropertyName RequestedClientCoordinates -NotePropertyValue @($ClickX,$ClickY)
  $clarityCapture|Add-Member -NotePropertyName WheelSteps -NotePropertyValue $(if($WheelX -ge 0){$WheelSteps}else{0})
  $clarityCaptureJson=$clarityCapture|ConvertTo-Json -Depth 5
  $clarityEvidence=Join-Path $clarityRepo ('design_refs/shop_infinite_scroll_20261017/live/'+[IO.Path]::GetFileNameWithoutExtension($Screenshot)+'.json')
  $clarityCaptureJson|Set-Content -LiteralPath $clarityEvidence -Encoding utf8
  Write-Output $clarityCaptureJson
 }
}finally{[void][CollectionClarityInput]::SetThreadDpiAwarenessContext($clarityDpi)}
