param([switch]$Show,[string]$Screenshot,[int]$ClickX=-1,[int]$ClickY=-1,[switch]$Escape,[int]$PointerX=-1,[int]$PointerY=-1,[switch]$PreviewOnly,[ValidateSet('F7','F8','WheelUp','WheelDown')][string]$PreviewInput,[switch]$CenterPointer)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class HandoffWindow {
 public delegate bool EnumProc(IntPtr hwnd, IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int n);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref Point p);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint dx,uint dy,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 public struct Rect {public int Left,Top,Right,Bottom;}
 public struct Point {public int X,Y;}
}
'@
$game=Get-Process dota2 -ErrorAction Stop | Select-Object -First 1
$details=Get-CimInstance Win32_Process -Filter "ProcessId=$($game.Id)"
if($details.CommandLine -notmatch '-addon\s+survival(?:\s|$)'){
    $proofToken='SURVIVAL_WINDOW_'+[Guid]::NewGuid().ToString('N')
    $proofDir=Join-Path $PSScriptRoot '../../output/map_window_check'
    New-Item -ItemType Directory -Force -Path $proofDir | Out-Null
    $proofFile=Join-Path $proofDir 'request.json'
    $requests=@(@{name='dota_run_lua';arguments=@{code="if IsInToolsMode() and (GetMapName() == 'template_map' or GetMapName() == 'survival_c6') then print('$proofToken') end"}})
    [IO.File]::WriteAllText($proofFile,(ConvertTo-Json -InputObject $requests -Depth 5 -Compress))
    & node (Join-Path $PSScriptRoot 'console.cjs') --file $proofFile --timeout-ms 2000 --expect $proofToken | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Not a verified survival Workshop session; refusing to show/capture another game'}
}
$script:gameWindows=@()
[HandoffWindow]::EnumWindows({param($handle,$arg)
    $owner=0;[void][HandoffWindow]::GetWindowThreadProcessId($handle,[ref]$owner)
    if($owner -eq $game.Id){$title=[Text.StringBuilder]::new(512);[void][HandoffWindow]::GetWindowText($handle,$title,512);$rect=[HandoffWindow+Rect]::new();[void][HandoffWindow]::GetClientRect($handle,[ref]$rect);$script:gameWindows+= [pscustomobject]@{Handle=$handle;Title=$title.ToString();Width=$rect.Right;Height=$rect.Bottom;Visible=[HandoffWindow]::IsWindowVisible($handle)}}
    return $true
},[IntPtr]::Zero) | Out-Null
$gameWindows | Format-Table
$window=$gameWindows | Where-Object {$_.Title -eq 'Dota 2'} | Sort-Object Width -Descending | Select-Object -First 1
if(-not $window){throw 'Requested test window not found'}
if($PreviewOnly){
    foreach($other in $gameWindows | Where-Object {$_.Title -in @('Asset Browser','Stall Detected','Panorama Debugger')}){[void][HandoffWindow]::ShowWindow($other.Handle,0)}
    $script:vconsoleIds=@(Get-Process vconsole2 -ErrorAction SilentlyContinue | ForEach-Object Id)
    [HandoffWindow]::EnumWindows({param($handle,$arg)
        $owner=0;[void][HandoffWindow]::GetWindowThreadProcessId($handle,[ref]$owner)
        if($script:vconsoleIds -contains $owner){[void][HandoffWindow]::ShowWindow($handle,0)}
        return $true
    },[IntPtr]::Zero) | Out-Null
}
if($Show){[void][HandoffWindow]::ShowWindow($window.Handle,9);[void][HandoffWindow]::SetForegroundWindow($window.Handle);Start-Sleep -Milliseconds 750}
$currentRect=[HandoffWindow+Rect]::new();[void][HandoffWindow]::GetClientRect($window.Handle,[ref]$currentRect)
$window.Width=$currentRect.Right;$window.Height=$currentRect.Bottom
$origin=[HandoffWindow+Point]::new();[void][HandoffWindow]::ClientToScreen($window.Handle,[ref]$origin)
if($CenterPointer){
    if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Test game is not foreground; refusing pointer movement'}
    [void][HandoffWindow]::SetCursorPos($origin.X+[int]($window.Width/2),$origin.Y+[int]($window.Height/2))
}
if($Escape) {
    if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Test game is not foreground; refusing input'}
    [HandoffWindow]::keybd_event(27,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [HandoffWindow]::keybd_event(27,0,2,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
}
if($ClickX -ge 0 -or $ClickY -ge 0) {
    if($ClickX -lt 0 -or $ClickY -lt 0 -or $ClickX -ge $window.Width -or $ClickY -ge $window.Height){throw 'Click outside test game client'}
    if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Test game is not foreground; refusing input'}
    $previousCursor=[Windows.Forms.Cursor]::Position
    [void][HandoffWindow]::SetCursorPos($origin.X+$ClickX,$origin.Y+$ClickY)
    Start-Sleep -Milliseconds 100
    if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed; refusing input'}
    [HandoffWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    [HandoffWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
    [Windows.Forms.Cursor]::Position=$previousCursor
}
if($PreviewInput) {
    if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Test game is not foreground; refusing preview input'}
    if($PreviewInput -like 'Wheel*') {
        [void][HandoffWindow]::SetCursorPos($origin.X+[int]($window.Width/2),$origin.Y+[int]($window.Height/2))
        $wheelData=if($PreviewInput -eq 'WheelUp'){[uint32]120}else{[uint32]4294967176}
        [HandoffWindow]::mouse_event(2048,0,0,$wheelData,[UIntPtr]::Zero)
    } else {
        $previewKeyCode=@{F7=118;F8=119}[$PreviewInput]
        [HandoffWindow]::keybd_event($previewKeyCode,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 100
        [HandoffWindow]::keybd_event($previewKeyCode,0,2,[UIntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 750
}
if($Screenshot) {
    if([IO.Path]::GetFileName($Screenshot) -ne $Screenshot){throw 'Screenshot must be a file name'}
    $bitmap=[Drawing.Bitmap]::new($window.Width,$window.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
    try {$graphics.CopyFromScreen($origin.X,$origin.Y,0,0,$bitmap.Size);$folder=Join-Path $PSScriptRoot '../../output/map_build_c6';New-Item -ItemType Directory -Force $folder | Out-Null;$bitmap.Save((Join-Path $folder $Screenshot),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
}
if($PointerX -ge 0 -or $PointerY -ge 0){
    if($PointerX -lt 0 -or $PointerY -lt 0 -or $PointerX -ge $window.Width -or $PointerY -ge $window.Height){throw 'Pointer outside test game client'}
    if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Test game is not foreground; refusing input'}
    [void][HandoffWindow]::SetCursorPos($origin.X+$PointerX,$origin.Y+$PointerY)
}
