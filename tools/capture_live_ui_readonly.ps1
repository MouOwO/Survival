[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$GameProcessId,
    [Parameter(Mandatory=$true)][string]$PngBasename
)
# Captures an already foreground survival tools client. This script performs no
# input, focus, window-state, game-state, console or network operation.
$ErrorActionPreference='Stop'
if($PngBasename -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*\.png$') {
    throw 'PngBasename must be a safe PNG file name (letters, digits, underscore or hyphen), without a directory.'
}
$captureWorkspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$captureDirectory=[IO.Path]::GetFullPath((Join-Path $captureWorkspace 'design_refs/menus_v10/work/native'))
if(-not $captureDirectory.StartsWith($captureWorkspace+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Capture directory is outside the workspace.'
}
$capturePngPath=Join-Path $captureDirectory $PngBasename
$captureJsonPath=Join-Path $captureDirectory ([IO.Path]::GetFileNameWithoutExtension($PngBasename)+'.json')
if([IO.File]::Exists($capturePngPath) -or [IO.File]::Exists($captureJsonPath)) {
    throw 'Capture basename already exists; refusing to overwrite PNG or metadata.'
}

if(-not ('LiveUIReadonlyCaptureV1' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class LiveUIReadonlyCaptureV1 {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    public class WindowInfo { public long Hwnd; public uint Pid; public string Title; public int Width, Height; }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr data);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int length);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hwnd, ref Point point);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] public static extern bool AreDpiAwarenessContextsEqual(IntPtr first, IntPtr second);
    public static WindowInfo[] FindWindows(uint requestedPid) {
        var result = new List<WindowInfo>();
        EnumProc callback = (hwnd, data) => {
            uint pid; GetWindowThreadProcessId(hwnd, out pid);
            if(pid != requestedPid || !IsWindowVisible(hwnd) || IsIconic(hwnd)) return true;
            var title = new StringBuilder(512); GetWindowText(hwnd, title, title.Capacity);
            if(title.ToString() != "Dota 2") return true;
            Rect rect;
            if(GetClientRect(hwnd, out rect) && rect.Right - rect.Left >= 640 && rect.Bottom - rect.Top >= 360) {
                result.Add(new WindowInfo { Hwnd=hwnd.ToInt64(), Pid=pid, Title=title.ToString(),
                    Width=rect.Right-rect.Left, Height=rect.Bottom-rect.Top });
            }
            return true;
        };
        if(!EnumWindows(callback, IntPtr.Zero)) throw new InvalidOperationException("Window enumeration failed.");
        return result.ToArray();
    }
}
'@
}

function Get-VerifiedProcess {
    # The command line is inspected locally only and is never returned or logged.
    $details=Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId" -ErrorAction Stop
    if($null -eq $details -or $details.Name -ine 'dota2.exe') { throw 'Requested PID is not a Dota 2 process.' }
    $toolsContract=($details.CommandLine -match '(?:^|\s)-tools(?:\s|$)') -and
        ($details.CommandLine -match '(?:^|\s)-addon\s+"?survival"?(?:\s|$)')
    if(-not $toolsContract -or $null -eq $details.CreationDate) {
        throw 'Requested PID is not an explicitly launched survival tools client.'
    }
    return [pscustomobject]@{pid=$GameProcessId;created_utc=$details.CreationDate.ToUniversalTime().ToString('o');survival_tools_verified=$true}
}

function Get-VerifiedWindowSnapshot {
    if(-not [LiveUIReadonlyCaptureV1]::AreDpiAwarenessContextsEqual(
        [LiveUIReadonlyCaptureV1]::GetThreadDpiAwarenessContext(),$captureDpiV2)) {
        throw 'Physical Per-Monitor V2 coordinate context was lost.'
    }
    $candidates=@([LiveUIReadonlyCaptureV1]::FindWindows([uint32]$GameProcessId))
    if($candidates.Count -ne 1) { throw 'Expected exactly one visible, non-minimized Dota 2 client of at least 640x360.' }
    $target=$candidates[0]
    $window=[IntPtr]::new($target.Hwnd)
    if(-not [LiveUIReadonlyCaptureV1]::IsWindow($window) -or [LiveUIReadonlyCaptureV1]::IsHungAppWindow($window)) {
        throw 'Requested Dota 2 window is invalid or hung.'
    }
    $foreground=[LiveUIReadonlyCaptureV1]::GetForegroundWindow()
    [uint32]$foregroundOwner=0
    [void][LiveUIReadonlyCaptureV1]::GetWindowThreadProcessId($foreground,[ref]$foregroundOwner)
    if($foreground -ne $window -or $foregroundOwner -ne $GameProcessId) {
        throw 'Requested Dota 2 window is not already foreground.'
    }
    $rect=[LiveUIReadonlyCaptureV1+Rect]::new()
    if(-not [LiveUIReadonlyCaptureV1]::GetClientRect($window,[ref]$rect)) { throw 'Client rectangle could not be read.' }
    $origin=[LiveUIReadonlyCaptureV1+Point]::new();$origin.X=$rect.Left;$origin.Y=$rect.Top
    $end=[LiveUIReadonlyCaptureV1+Point]::new();$end.X=$rect.Right;$end.Y=$rect.Bottom
    if(-not [LiveUIReadonlyCaptureV1]::ClientToScreen($window,[ref]$origin) -or
        -not [LiveUIReadonlyCaptureV1]::ClientToScreen($window,[ref]$end)) { throw 'Physical client bounds could not be read.' }
    $width=$rect.Right-$rect.Left;$height=$rect.Bottom-$rect.Top
    if($width -lt 640 -or $height -lt 360 -or $end.X-$origin.X -ne $width -or $end.Y-$origin.Y -ne $height) {
        throw 'Physical client geometry is inconsistent.'
    }
    $desktopX=[LiveUIReadonlyCaptureV1]::GetSystemMetrics(76)
    $desktopY=[LiveUIReadonlyCaptureV1]::GetSystemMetrics(77)
    $desktopWidth=[LiveUIReadonlyCaptureV1]::GetSystemMetrics(78)
    $desktopHeight=[LiveUIReadonlyCaptureV1]::GetSystemMetrics(79)
    if($origin.X -lt $desktopX -or $origin.Y -lt $desktopY -or
        $end.X -gt $desktopX+$desktopWidth -or $end.Y -gt $desktopY+$desktopHeight) {
        throw 'The entire physical client is not on the virtual desktop.'
    }
    $cornerOwners=@()
    foreach($corner in @(@(0,0),@(($width-1),0),@(0,($height-1)),@(($width-1),($height-1)))) {
        $point=[LiveUIReadonlyCaptureV1+Point]::new();$point.X=$origin.X+$corner[0];$point.Y=$origin.Y+$corner[1]
        $pointWindow=[LiveUIReadonlyCaptureV1]::WindowFromPoint($point)
        [uint32]$pointOwner=0
        [void][LiveUIReadonlyCaptureV1]::GetWindowThreadProcessId($pointWindow,[ref]$pointOwner)
        if($pointOwner -ne $GameProcessId -or [LiveUIReadonlyCaptureV1]::GetAncestor($pointWindow,2) -ne $window) {
            throw 'A physical client corner is covered by another window.'
        }
        $cornerOwners+=[pscustomobject]@{client_x=$corner[0];client_y=$corner[1];pid=$pointOwner;root_hwnd=$target.Hwnd;owned=$true}
    }
    return [pscustomobject]@{
        pid=$GameProcessId;hwnd=$target.Hwnd;title='Dota 2';foreground=$true;visible=$true;iconic=$false;hung=$false
        client_x=$origin.X;client_y=$origin.Y;client_width=$width;client_height=$height
        dpi=[LiveUIReadonlyCaptureV1]::GetDpiForWindow($window);corner_owners=$cornerOwners
    }
}

$captureDpiV2=[IntPtr]::new(-4)
$capturePreviousDpi=[LiveUIReadonlyCaptureV1]::SetThreadDpiAwarenessContext($captureDpiV2)
if($capturePreviousDpi -eq [IntPtr]::Zero) { throw 'Cannot establish Per-Monitor V2 physical coordinates.' }
$captureBitmap=$null;$captureGraphics=$null;$captureMemory=$null
$capturePngStream=$null;$captureJsonStream=$null
$captureOwnPng=$false;$captureOwnJson=$false;$capturePublished=$false
try {
    $captureProcessBefore=Get-VerifiedProcess
    $captureBefore=Get-VerifiedWindowSnapshot
    Add-Type -AssemblyName System.Drawing
    $captureStarted=[DateTime]::UtcNow
    $captureBitmap=[Drawing.Bitmap]::new($captureBefore.client_width,$captureBefore.client_height)
    $captureGraphics=[Drawing.Graphics]::FromImage($captureBitmap)
    $captureGraphics.CopyFromScreen($captureBefore.client_x,$captureBefore.client_y,0,0,
        $captureBitmap.Size,[Drawing.CopyPixelOperation]::SourceCopy)
    $captureAfter=Get-VerifiedWindowSnapshot
    $captureProcessAfter=Get-VerifiedProcess
    foreach($field in @('pid','hwnd','client_x','client_y','client_width','client_height','dpi')) {
        if($captureBefore.$field -ne $captureAfter.$field) { throw 'Window identity or physical geometry changed during capture; no image will be published.' }
    }
    if($captureProcessBefore.created_utc -ne $captureProcessAfter.created_utc) {
        throw 'Process identity changed during capture; no image will be published.'
    }
    $captureEnded=[DateTime]::UtcNow
    $captureMemory=[IO.MemoryStream]::new()
    $captureBitmap.Save($captureMemory,[Drawing.Imaging.ImageFormat]::Png)
    $captureBytes=$captureMemory.ToArray()
    $captureMetadata=[ordered]@{
        schema_version=1;helper='capture_live_ui_readonly.ps1';capture_valid=$true
        scope='One already foreground survival tools Dota 2 client; screenshots only'
        coordinate_space='physical client pixels';thread_dpi_context='PER_MONITOR_AWARE_V2'
        started_utc=$captureStarted.ToString('o');ended_utc=$captureEnded.ToString('o')
        survival_tools_verified=$true;process_created_utc=$captureProcessBefore.created_utc
        before=$captureBefore;after=$captureAfter;png=$PngBasename;png_bytes=$captureBytes.Length
        limitation='Four corners verified; an interior-only overlay and game UI authenticity require visual review.'
    }
    $captureJsonBytes=[Text.UTF8Encoding]::new($false).GetBytes(($captureMetadata | ConvertTo-Json -Depth 8))
    [void][IO.Directory]::CreateDirectory($captureDirectory)
    # Exclusive CreateNew protects against both preexisting files and publication races.
    $capturePngStream=[IO.File]::Open($capturePngPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $captureOwnPng=$true
    $captureJsonStream=[IO.File]::Open($captureJsonPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $captureOwnJson=$true
    $capturePngStream.Write($captureBytes,0,$captureBytes.Length);$capturePngStream.Flush()
    $captureJsonStream.Write($captureJsonBytes,0,$captureJsonBytes.Length);$captureJsonStream.Flush()
    $capturePublished=$true
} finally {
    if($null -ne $captureJsonStream) { $captureJsonStream.Dispose() }
    if($null -ne $capturePngStream) { $capturePngStream.Dispose() }
    if($null -ne $captureMemory) { $captureMemory.Dispose() }
    if($null -ne $captureGraphics) { $captureGraphics.Dispose() }
    if($null -ne $captureBitmap) { $captureBitmap.Dispose() }
    [void][LiveUIReadonlyCaptureV1]::SetThreadDpiAwarenessContext($capturePreviousDpi)
    # Only this invocation's newly reserved output files are removed on failure.
    if(-not $capturePublished) {
        if($captureOwnJson) { [IO.File]::Delete($captureJsonPath) }
        if($captureOwnPng) { [IO.File]::Delete($capturePngPath) }
    }
}
[pscustomobject]@{png=$capturePngPath;metadata=$captureJsonPath;pid=$GameProcessId;hwnd=$captureAfter.hwnd;
    width=$captureAfter.client_width;height=$captureAfter.client_height;capture_valid=$true} | ConvertTo-Json -Compress
