param(
    [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$ProcessId,
    [string]$Screenshot,
    [int]$ClickX=-1,
    [int]$ClickY=-1,
    [int]$PointerX=-1,
    [int]$PointerY=-1,
    [ValidateSet('F7','F8')][string]$ReviewKey,
    [ValidateRange(0,5000)][int]$CaptureDelayMs=250
)
# Coordinates are physical pixels relative to the captured game client, not the desktop.
# This helper never activates, restores, hides or resizes a window, and has no console socket.
$ErrorActionPreference='Stop'
if(-not ('ArchiveV10Window' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ArchiveV10Window {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct MouseInput { public int X,Y; public uint Data,Flags,Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] public struct KeyboardInput { public ushort VirtualKey,Scan; public uint Flags,Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public MouseInput Mouse; [FieldOffset(0)] public KeyboardInput Keyboard; }
    [StructLayout(LayoutKind.Sequential)] public struct Input { public uint Type; public InputUnion Value; }
    [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool AreDpiAwarenessContextsEqual(IntPtr a, IntPtr b);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr window);
    [DllImport("user32.dll")] public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool EnumWindows(EnumProc cb,IntPtr data);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window,out uint owner);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window,StringBuilder text,int length);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool GetClientRect(IntPtr window,out Rect rect);
    [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool ClientToScreen(IntPtr window,ref Point point);
    [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool GetPhysicalCursorPos(out Point point);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr window,uint flags);
    [DllImport("user32.dll",SetLastError=true)] public static extern uint SendInput(uint count,Input[] inputs,int size);
    public static void LeftClick() {
        var down = new Input { Type=0, Value=new InputUnion { Mouse=new MouseInput { Flags=2 } } };
        var up = new Input { Type=0, Value=new InputUnion { Mouse=new MouseInput { Flags=4 } } };
        int size=Marshal.SizeOf(typeof(Input));
        if(SendInput(1,new Input[] {down},size) != 1)
            throw new InvalidOperationException("SendInput did not deliver mouse down.");
        try {System.Threading.Thread.Sleep(100);}
        finally {
            if(SendInput(1,new Input[] {up},size) != 1)
                throw new InvalidOperationException("SendInput did not deliver mouse up.");
        }
    }
    public static void ReviewKeyEvent(ushort virtualKey,bool release) {
        if(virtualKey != 118 && virtualKey != 119)
            throw new ArgumentOutOfRangeException("virtualKey","Only F7/F8 review keys are supported.");
        var input = new Input { Type=1, Value=new InputUnion { Keyboard=new KeyboardInput { VirtualKey=virtualKey, Flags=release ? 2u : 0u } } };
        if(SendInput(1,new Input[] {input},Marshal.SizeOf(typeof(Input))) != 1)
            throw new InvalidOperationException("SendInput did not deliver the review key event.");
    }
}
'@
}

# This is deliberately before EnumWindows, geometry queries, Drawing and cursor APIs.
$v10DpiV2=[IntPtr]::new(-4)
$v10ProcessDpiSet=[ArchiveV10Window]::SetProcessDpiAwarenessContext($v10DpiV2)
$v10ProcessDpiError=if($v10ProcessDpiSet){0}else{[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
# PowerShell can already have process awareness from its manifest; a thread override is valid.
$v10PreviousThreadDpi=[ArchiveV10Window]::SetThreadDpiAwarenessContext($v10DpiV2)
if($v10PreviousThreadDpi -eq [IntPtr]::Zero){throw 'Cannot establish Per-Monitor V2 DPI awareness; refusing coordinate operations.'}
try {
    function Assert-PhysicalDpi {
        [void][ArchiveV10Window]::SetThreadDpiAwarenessContext($v10DpiV2)
        if(-not [ArchiveV10Window]::AreDpiAwarenessContextsEqual([ArchiveV10Window]::GetThreadDpiAwarenessContext(),$v10DpiV2)) {
            throw 'Per-Monitor V2 thread context was lost; refusing coordinate operations.'
        }
    }
    Assert-PhysicalDpi
    $v10Game=Get-Process -Id $ProcessId -ErrorAction Stop
    if($v10Game.ProcessName -ne 'dota2'){throw "PID $ProcessId is not dota2; refusing another process."}
    $v10ProcessDetails=Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
    $v10VerifiedTools=($v10ProcessDetails.CommandLine -match '(?:^|\s)-tools(?:\s|$)') -and
        ($v10ProcessDetails.CommandLine -match '(?:^|\s)-addon\s+"?survival"?(?:\s|$)')
    if(-not $v10VerifiedTools){throw 'Requested PID is not an explicitly launched survival tools session; no socket fallback is permitted.'}
    $v10Windows=[Collections.Generic.List[object]]::new()
    [void][ArchiveV10Window]::EnumWindows({param($handle,$unused)
        $v10Owner=[uint32]0
        [void][ArchiveV10Window]::GetWindowThreadProcessId($handle,[ref]$v10Owner)
        if($v10Owner -eq $ProcessId -and [ArchiveV10Window]::IsWindowVisible($handle)) {
            $v10Title=[Text.StringBuilder]::new(512)
            [void][ArchiveV10Window]::GetWindowText($handle,$v10Title,512)
            $v10Rect=[ArchiveV10Window+Rect]::new()
            if([ArchiveV10Window]::GetClientRect($handle,[ref]$v10Rect)) {
                $v10Windows.Add([pscustomobject]@{Handle=$handle;Title=$v10Title.ToString();Width=$v10Rect.Right-$v10Rect.Left;Height=$v10Rect.Bottom-$v10Rect.Top})
            }
        }
        return $true
    },[IntPtr]::Zero)
    $v10Target=$v10Windows | Where-Object {$_.Title -eq 'Dota 2' -and $_.Width -gt 0 -and $_.Height -gt 0} |
        Sort-Object Width -Descending | Select-Object -First 1
    if(-not $v10Target){throw "Visible Dota 2 client window not found in PID $ProcessId."}

    function Get-TargetGeometry {
        Assert-PhysicalDpi
        $v10Owner=[uint32]0
        [void][ArchiveV10Window]::GetWindowThreadProcessId($v10Target.Handle,[ref]$v10Owner)
        if($v10Owner -ne $ProcessId -or -not [ArchiveV10Window]::IsWindow($v10Target.Handle)){throw 'Target window ownership changed.'}
        if([ArchiveV10Window]::IsIconic($v10Target.Handle)){throw 'Target is minimized; this helper does not restore windows.'}
        $v10Rect=[ArchiveV10Window+Rect]::new()
        $v10Origin=[ArchiveV10Window+Point]::new()
        $v10BottomRight=[ArchiveV10Window+Point]::new()
        if(-not [ArchiveV10Window]::GetClientRect($v10Target.Handle,[ref]$v10Rect)){throw 'GetClientRect failed.'}
        $v10BottomRight.X=$v10Rect.Right;$v10BottomRight.Y=$v10Rect.Bottom
        if(-not [ArchiveV10Window]::ClientToScreen($v10Target.Handle,[ref]$v10Origin) -or
            -not [ArchiveV10Window]::ClientToScreen($v10Target.Handle,[ref]$v10BottomRight)){throw 'ClientToScreen failed.'}
        $v10Width=$v10Rect.Right-$v10Rect.Left;$v10Height=$v10Rect.Bottom-$v10Rect.Top
        if($v10Width -le 0 -or $v10Height -le 0 -or $v10BottomRight.X-$v10Origin.X -ne $v10Width -or
            $v10BottomRight.Y-$v10Origin.Y -ne $v10Height){throw 'Physical client geometry is inconsistent; refusing input or capture.'}
        return [pscustomobject]@{X=$v10Origin.X;Y=$v10Origin.Y;Width=$v10Width;Height=$v10Height}
    }
    function Assert-TargetForeground {
        if([ArchiveV10Window]::GetForegroundWindow() -ne $v10Target.Handle){throw 'Requested game is not foreground; this helper will not steal focus.'}
    }
    function Get-TargetPoint([int]$x,[int]$y) {
        Assert-TargetForeground
        $v10Geometry=Get-TargetGeometry
        if($x -lt 0 -or $y -lt 0 -or $x -ge $v10Geometry.Width -or $y -ge $v10Geometry.Height){throw 'Coordinates are outside the physical game client.'}
        $v10Point=[ArchiveV10Window+Point]::new();$v10Point.X=$v10Geometry.X+$x;$v10Point.Y=$v10Geometry.Y+$y
        $v10PointWindow=[ArchiveV10Window]::WindowFromPoint($v10Point)
        if([ArchiveV10Window]::GetAncestor($v10PointWindow,2) -ne $v10Target.Handle){throw 'Another window covers the requested point; refusing input.'}
        return $v10Point
    }
    function Move-TargetPointer([int]$x,[int]$y) {
        $v10Point=Get-TargetPoint $x $y
        if(-not [ArchiveV10Window]::SetCursorPos($v10Point.X,$v10Point.Y)){throw 'SetCursorPos failed.'}
        $v10Actual=[ArchiveV10Window+Point]::new()
        if(-not [ArchiveV10Window]::GetPhysicalCursorPos([ref]$v10Actual) -or
            $v10Actual.X -ne $v10Point.X -or $v10Actual.Y -ne $v10Point.Y){throw 'Physical pointer verification failed; refusing click.'}
    }

    # Reject incomplete coordinate pairs before moving the pointer.
    if(($ClickX -ge 0) -ne ($ClickY -ge 0)){throw 'Provide both ClickX and ClickY.'}
    if(($PointerX -ge 0) -ne ($PointerY -ge 0)){throw 'Provide both PointerX and PointerY.'}
    if($Screenshot -and ([IO.Path]::GetFileName($Screenshot) -ne $Screenshot -or [IO.Path]::GetExtension($Screenshot) -ne '.png')) {
        throw 'Screenshot must be a PNG file name, without a directory.'
    }
    $v10ClickSent=$false;$v10PointerMoved=$false;$v10ScreenshotPath=$null;$v10ReviewKeySent=$null
    if($ClickX -ge 0) {
        Move-TargetPointer $ClickX $ClickY
        $v10PointerMoved=$true
        Start-Sleep -Milliseconds 80
        $v10ClickPoint=Get-TargetPoint $ClickX $ClickY
        $v10ClickActual=[ArchiveV10Window+Point]::new()
        if(-not [ArchiveV10Window]::GetPhysicalCursorPos([ref]$v10ClickActual) -or
            $v10ClickActual.X -ne $v10ClickPoint.X -or $v10ClickActual.Y -ne $v10ClickPoint.Y){
            throw 'Game repositioned the pointer before click; refusing input at a different point.'
        }
        [ArchiveV10Window]::LeftClick()
        Assert-TargetForeground
        $v10ClickSent=$true
    }
    # Pointer follows click, allowing a caller to click a category then hover an item.
    if($PointerX -ge 0){Move-TargetPointer $PointerX $PointerY;$v10PointerMoved=$true}
    if($ReviewKey) {
        Assert-TargetForeground
        Assert-PhysicalDpi
        $v10ReviewVirtualKey=[uint16](@{F7=118;F8=119}[$ReviewKey])
        [ArchiveV10Window]::ReviewKeyEvent($v10ReviewVirtualKey,$false)
        # Always release a delivered down event, including when foreground changes.
        try {Start-Sleep -Milliseconds 100} finally {[ArchiveV10Window]::ReviewKeyEvent($v10ReviewVirtualKey,$true)}
        Assert-TargetForeground
        $v10ReviewKeySent=$ReviewKey
    }
    if($Screenshot) {
        if($CaptureDelayMs -gt 0){Start-Sleep -Milliseconds $CaptureDelayMs}
        Assert-TargetForeground
        $v10Geometry=Get-TargetGeometry
        # All four client corners must still be on the target rather than an overlapping window.
        foreach($v10Corner in @(@(0,0),@(($v10Geometry.Width-1),0),@(0,($v10Geometry.Height-1)),@(($v10Geometry.Width-1),($v10Geometry.Height-1)))) {
            [void](Get-TargetPoint $v10Corner[0] $v10Corner[1])
        }
        Add-Type -AssemblyName System.Drawing
        Assert-PhysicalDpi
        $v10Bitmap=[Drawing.Bitmap]::new($v10Geometry.Width,$v10Geometry.Height)
        $v10Graphics=[Drawing.Graphics]::FromImage($v10Bitmap)
        try {
            $v10Graphics.CopyFromScreen($v10Geometry.X,$v10Geometry.Y,0,0,$v10Bitmap.Size,[Drawing.CopyPixelOperation]::SourceCopy)
            $v10GeometryAfter=Get-TargetGeometry
            if($v10GeometryAfter.X -ne $v10Geometry.X -or $v10GeometryAfter.Y -ne $v10Geometry.Y -or
                $v10GeometryAfter.Width -ne $v10Geometry.Width -or $v10GeometryAfter.Height -ne $v10Geometry.Height){throw 'Window moved during capture; image was not saved.'}
            $v10CaptureFolder=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../design_refs/archive_v10/work/native'))
            [void][IO.Directory]::CreateDirectory($v10CaptureFolder)
            $v10ScreenshotPath=Join-Path $v10CaptureFolder $Screenshot
            $v10Bitmap.Save($v10ScreenshotPath,[Drawing.Imaging.ImageFormat]::Png)
        } finally {$v10Graphics.Dispose();$v10Bitmap.Dispose()}
    }
    $v10Geometry=Get-TargetGeometry
    $v10Cursor=[ArchiveV10Window+Point]::new();[void][ArchiveV10Window]::GetPhysicalCursorPos([ref]$v10Cursor)
    [pscustomobject]@{
        ProcessId=$ProcessId;WindowHandle=$v10Target.Handle.ToInt64();Title=$v10Target.Title
        CoordinateSpace='physical client pixels';ClientX=$v10Geometry.X;ClientY=$v10Geometry.Y
        Width=$v10Geometry.Width;Height=$v10Geometry.Height;Dpi=[ArchiveV10Window]::GetDpiForWindow($v10Target.Handle)
        ThreadDpiContext='PER_MONITOR_AWARE_V2';ProcessDpiSet=$v10ProcessDpiSet;ProcessDpiError=$v10ProcessDpiError
        GameDpiAwareness=[ArchiveV10Window]::GetAwarenessFromDpiAwarenessContext([ArchiveV10Window]::GetWindowDpiAwarenessContext($v10Target.Handle))
        Foreground=([ArchiveV10Window]::GetForegroundWindow() -eq $v10Target.Handle)
        CursorClientX=$v10Cursor.X-$v10Geometry.X;CursorClientY=$v10Cursor.Y-$v10Geometry.Y
        PointerMoved=$v10PointerMoved;ClickSent=$v10ClickSent;ReviewKeySent=$v10ReviewKeySent;Screenshot=$v10ScreenshotPath
    } | ConvertTo-Json -Depth 3
} finally {[void][ArchiveV10Window]::SetThreadDpiAwarenessContext($v10PreviousThreadDpi)}
