param(
    [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$GameProcessId,
    [Parameter(Mandatory=$true)][ValidateRange(0,32767)][int]$ClientStartX,
    [Parameter(Mandatory=$true)][ValidateRange(0,32767)][int]$ClientStartY,
    [Parameter(Mandatory=$true)][ValidateRange(0,32767)][int]$ClientEndY,
    [Parameter(Mandatory=$true)][string]$Screenshot
)
# Drag only the manually verified right scrollbar track. No wheel, product click,
# console command, account access, checkout, or game configuration write occurs.
$ErrorActionPreference='Stop'
$dragRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dragOut=[IO.Path]::GetFullPath((Join-Path $dragRepo 'output/shop_scrollbar_right_20261017'))
[void][IO.Directory]::CreateDirectory($dragOut)
$dragAfterPath=if([IO.Path]::IsPathRooted($Screenshot)){
    [IO.Path]::GetFullPath($Screenshot)
} elseif($Screenshot -match '[/\\]'){
    [IO.Path]::GetFullPath((Join-Path $dragRepo $Screenshot))
} else {[IO.Path]::GetFullPath((Join-Path $dragOut $Screenshot))}
if(-not $dragAfterPath.StartsWith($dragOut+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Screenshot must stay inside output/shop_scrollbar_right_20261017.'
}
if([IO.Path]::GetExtension($dragAfterPath) -ine '.png'){throw 'Screenshot must be a PNG filename.'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dragAfterPath))
$dragStem=[IO.Path]::GetFileNameWithoutExtension($dragAfterPath)
$dragBeforePath=Join-Path ([IO.Path]::GetDirectoryName($dragAfterPath)) ($dragStem+'_before.png')
$dragMetaPath=Join-Path $dragOut ($dragStem+'.json')
if($ClientEndY -eq $ClientStartY){throw 'A nonzero vertical drag is required.'}

$dragFocus=& (Join-Path $dragRepo 'tools/focus_live_perf_window.ps1') -GameProcessId $GameProcessId -SkipCursorCenter | ConvertFrom-Json
if(-not $dragFocus.selection_unique -or -not $dragFocus.foreground){throw 'A unique foreground Dota window is required.'}
$dragWindow=[IntPtr]::new([long]$dragFocus.window)
Add-Type -AssemblyName System.Drawing
if(-not ('ShopScrollbarDragInputV1' -as [type])){Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ShopScrollbarDragInputV1 {
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct Mouse {public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra;}
 [StructLayout(LayoutKind.Explicit)] public struct Union {[FieldOffset(0)]public Mouse Mouse;}
 [StructLayout(LayoutKind.Sequential)] public struct Input {public uint Type;public Union Value;}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out Rect rect);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window,ref Point point);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr window,uint flags);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int metric);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
 [DllImport("user32.dll",SetLastError=true)] public static extern uint SendInput(uint count,Input[] inputs,int size);
 [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool PrintWindow(IntPtr window,IntPtr dc,uint flags);
 public static void Move(int x,int y){
  int left=GetSystemMetrics(76),top=GetSystemMetrics(77),width=GetSystemMetrics(78),height=GetSystemMetrics(79);
  if(width<2||height<2||x<left||x>=left+width||y<top||y>=top+height)throw new InvalidOperationException("Drag point is outside the virtual desktop.");
  var input=new Input{Type=0,Value=new Union{Mouse=new Mouse{X=(int)Math.Round((x-left)*65535.0/(width-1)),Y=(int)Math.Round((y-top)*65535.0/(height-1)),Flags=0xc001}}};
  if(SendInput(1,new Input[]{input},Marshal.SizeOf(typeof(Input)))!=1)throw new InvalidOperationException("Mouse movement delivery failed.");
 }
 public static bool Button(uint flag){
  var input=new Input{Type=0,Value=new Union{Mouse=new Mouse{Flags=flag}}};
  return SendInput(1,new Input[]{input},Marshal.SizeOf(typeof(Input)))==1;
 }
}
'@}

function Get-VerifiedDragClient {
    param([switch]$RequireForeground)
    $dragCandidates=@([LivePerfFocusV2]::FindWindows([uint32]$GameProcessId) | Where-Object {
        $_.Title -ceq 'Dota 2' -and $_.Visible -and $_.ClientRectValid -and $_.ClientWidth -ge 640 -and $_.ClientHeight -ge 360
    })
    if($dragCandidates.Count -ne 1 -or $dragCandidates[0].Hwnd -ne $dragWindow.ToInt64()){
        throw 'The uniquely verified Dota window changed; drag aborted.'
    }
    if($dragCandidates[0].Iconic){throw 'The verified Dota window is minimized.'}
    if($RequireForeground -and [ShopScrollbarDragInputV1]::GetForegroundWindow() -ne $dragWindow){
        throw 'Dota lost foreground; no further drag movement is allowed.'
    }
    return $dragCandidates[0]
}
function Get-VerifiedDragPoint {
    param([int]$ClientY)
    $dragClient=Get-VerifiedDragClient -RequireForeground
    if($ClientStartX -lt [Math]::Floor($dragClient.ClientWidth/2) -or $ClientStartX -ge $dragClient.ClientWidth -or $ClientY -lt 0 -or $ClientY -ge $dragClient.ClientHeight){
        throw 'The requested right-track point is outside the verified right half of the client.'
    }
    if($dragClient.ClientWidth -ne $dragFocus.client_width -or $dragClient.ClientHeight -ne $dragFocus.client_height){throw 'Dota client dimensions changed during drag.'}
    $dragPoint=[ShopScrollbarDragInputV1+Point]::new();$dragPoint.X=$ClientStartX;$dragPoint.Y=$ClientY
    if(-not [ShopScrollbarDragInputV1]::ClientToScreen($dragWindow,[ref]$dragPoint)){throw 'Could not map the verified client drag point.'}
    if([ShopScrollbarDragInputV1]::GetAncestor([ShopScrollbarDragInputV1]::WindowFromPoint($dragPoint),2) -ne $dragWindow){
        throw 'The requested scrollbar point is covered by another window.'
    }
    return $dragPoint
}
function Save-VerifiedDragCapture {
    param([string]$Path)
    # Captures use this exact verified HWND, even if another window gains focus.
    # Input uses a stricter foreground check in Get-VerifiedDragPoint.
    $dragClient=Get-VerifiedDragClient
    $dragBitmap=[Drawing.Bitmap]::new($dragClient.ClientWidth,$dragClient.ClientHeight)
    $dragGraphics=[Drawing.Graphics]::FromImage($dragBitmap)
    $dragDc=[IntPtr]::Zero
    try{
        $dragDc=$dragGraphics.GetHdc()
        # PW_CLIENTONLY | PW_RENDERFULLCONTENT: PNG coordinates match client inputs.
        $dragCaptureOk=[ShopScrollbarDragInputV1]::PrintWindow($dragWindow,$dragDc,3)
        if(-not $dragCaptureOk){throw 'PrintWindow failed for the verified Dota HWND.'}
        $dragGraphics.ReleaseHdc($dragDc);$dragDc=[IntPtr]::Zero
        $dragBitmap.Save($Path,[Drawing.Imaging.ImageFormat]::Png)
    }finally{
        if($dragDc -ne [IntPtr]::Zero){$dragGraphics.ReleaseHdc($dragDc)}
        $dragGraphics.Dispose();$dragBitmap.Dispose()
    }
    return [ordered]@{path=$Path;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant();method='PrintWindow';flags=3;hwnd=$dragWindow.ToInt64();client_width=$dragClient.ClientWidth;client_height=$dragClient.ClientHeight}
}

$dragRecord=[ordered]@{
    at=[DateTime]::UtcNow.ToString('o');kind='native_right_scrollbar_mouse_drag';pid=$GameProcessId;hwnd=$dragWindow.ToInt64();
    noWheel=$true;noProductClick=$true;noAccountOrTransactionWrites=$true;focus=$dragFocus;
    requestedClientStart=@($ClientStartX,$ClientStartY);requestedClientEnd=@($ClientStartX,$ClientEndY);
    steps=24;stepDelayMs=20;inputMoves=0;mouseDownAttempted=$false;mouseUpDelivered=$false;status='STARTED'
}
$dragOldDpi=[ShopScrollbarDragInputV1]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
$dragFailure=$null
try{
    # Validate the whole constant-X route before any input, then recheck each step.
    for($dragIndex=0;$dragIndex -le $dragRecord.steps;$dragIndex++){
        $dragY=[int][Math]::Round($ClientStartY+($ClientEndY-$ClientStartY)*$dragIndex/$dragRecord.steps)
        [void](Get-VerifiedDragPoint -ClientY $dragY)
    }
    $dragRecord.before=Save-VerifiedDragCapture -Path $dragBeforePath
    $dragPoint=Get-VerifiedDragPoint -ClientY $ClientStartY
    [ShopScrollbarDragInputV1]::Move($dragPoint.X,$dragPoint.Y);$dragRecord.inputMoves++
    Start-Sleep -Milliseconds 100
    [void](Get-VerifiedDragPoint -ClientY $ClientStartY)
    $dragRecord.mouseDownAttempted=$true
    if(-not [ShopScrollbarDragInputV1]::Button(2)){throw 'Scrollbar mouse-down delivery failed.'}
    try{
        for($dragIndex=1;$dragIndex -le $dragRecord.steps;$dragIndex++){
            $dragY=[int][Math]::Round($ClientStartY+($ClientEndY-$ClientStartY)*$dragIndex/$dragRecord.steps)
            $dragPoint=Get-VerifiedDragPoint -ClientY $dragY
            [ShopScrollbarDragInputV1]::Move($dragPoint.X,$dragPoint.Y);$dragRecord.inputMoves++
            Start-Sleep -Milliseconds $dragRecord.stepDelayMs
        }
    }finally{
        $dragRecord.mouseUpDelivered=[ShopScrollbarDragInputV1]::Button(4)
    }
    if(-not $dragRecord.mouseUpDelivered){throw 'Scrollbar mouse-up delivery failed.'}
    Start-Sleep -Milliseconds 450
    $dragRecord.after=Save-VerifiedDragCapture -Path $dragAfterPath
    $dragRecord.status='INPUT_DELIVERED_COMPARE_SCREENSHOTS'
}catch{
    $dragFailure=$_;$dragRecord.status='FAILED';$dragRecord.failure=$_.Exception.Message
}finally{
    # Also release after a failed/partial SendInput call, regardless of foreground.
    if($dragRecord.mouseDownAttempted -and -not $dragRecord.mouseUpDelivered){$dragRecord.mouseUpDelivered=[ShopScrollbarDragInputV1]::Button(4)}
    [void][ShopScrollbarDragInputV1]::SetThreadDpiAwarenessContext($dragOldDpi)
    $dragRecord.finished=[DateTime]::UtcNow.ToString('o')
    $dragRecord|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $dragMetaPath -Encoding utf8
}
$dragRecord|ConvertTo-Json -Depth 8
if($dragFailure){throw $dragFailure}
