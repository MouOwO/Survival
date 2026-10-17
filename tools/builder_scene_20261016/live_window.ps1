param(
    [Parameter(Mandatory=$true)][int]$GameProcessId,
    [ValidateSet('CaptureSequence')][string]$Action = 'CaptureSequence',
    [string]$Tag = 'builder',
    [int]$FrameCount = 48,
    [int]$IntervalMs = 125
)
$ErrorActionPreference = 'Stop'
$sceneRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($Tag -cnotmatch '^[a-zA-Z0-9_-]+$') { throw 'Unsafe capture tag.' }
if ($FrameCount -lt 2 -or $FrameCount -gt 160 -or $IntervalMs -lt 50 -or $IntervalMs -gt 500) { throw 'Unbounded capture.' }
$sceneFocus = & (Join-Path $sceneRoot 'tools/focus_live_perf_window.ps1') -GameProcessId $GameProcessId -SkipCursorCenter | ConvertFrom-Json
$sceneProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$GameProcessId"
if ($sceneProcess.Name -ine 'dota2.exe' -or $sceneProcess.CommandLine -notmatch '(?:^|\s)-tools(?:\s|$)' -or $sceneProcess.CommandLine -notmatch '(?:^|\s)-addon\s+"?survival"?(?:\s|$)') { throw 'Not the verified survival tools client.' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BuilderSceneInputV1 {
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern bool ClientToScreen(IntPtr window,ref Point point);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
}
'@
$sceneWindow = [IntPtr]::new([long]$sceneFocus.window)
if ($Action -eq 'CaptureSequence') {
    Add-Type -AssemblyName System.Drawing
    $sceneOutput = Join-Path $sceneRoot ('output/builder_scene_20261016/' + $Tag)
    if (Test-Path -LiteralPath $sceneOutput) { throw 'Capture sequence already exists.' }
    [void][IO.Directory]::CreateDirectory($sceneOutput)
    $scenePriorDpi = [BuilderSceneInputV1]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
    $sceneOrigin = [BuilderSceneInputV1+Point]::new()
    if (-not [BuilderSceneInputV1]::ClientToScreen($sceneWindow,[ref]$sceneOrigin)) { throw 'Client origin unavailable.' }
    # Native client crop, recorded before pixels are sampled. Nothing is resized.
    $sceneCrop = @{x=470;y=750;width=155;height=148}
    if ($sceneFocus.client_width -ne 1600 -or $sceneFocus.client_height -ne 900) { throw 'This observation crop requires the measured 1600x900 client.' }
    $sceneFrames = @()
    $sceneClock = [Diagnostics.Stopwatch]::StartNew()
    try {
        for ($sceneIndex=0; $sceneIndex -lt $FrameCount; $sceneIndex++) {
            if ([BuilderSceneInputV1]::GetForegroundWindow() -ne $sceneWindow) { throw 'Game lost foreground during recording.' }
            $sceneFile = Join-Path $sceneOutput ('frame_{0:D3}.png' -f $sceneIndex)
            $sceneBitmap = [Drawing.Bitmap]::new($sceneCrop.width,$sceneCrop.height)
            $sceneGraphics = [Drawing.Graphics]::FromImage($sceneBitmap)
            try {
                $sceneGraphics.CopyFromScreen($sceneOrigin.X+$sceneCrop.x,$sceneOrigin.Y+$sceneCrop.y,0,0,$sceneBitmap.Size,[Drawing.CopyPixelOperation]::SourceCopy)
                $sceneFrames += @{frame=$sceneIndex;milliseconds=$sceneClock.Elapsed.TotalMilliseconds;file=(Split-Path -Leaf $sceneFile)}
                $sceneBitmap.Save($sceneFile,[Drawing.Imaging.ImageFormat]::Png)
            } finally {$sceneGraphics.Dispose();$sceneBitmap.Dispose()}
            $sceneRemaining = ($sceneIndex+1)*$IntervalMs-$sceneClock.Elapsed.TotalMilliseconds
            if ($sceneRemaining -gt 0) { Start-Sleep -Milliseconds ([int]$sceneRemaining) }
        }
    } finally {[void][BuilderSceneInputV1]::SetThreadDpiAwarenessContext($scenePriorDpi)}
    @{pid=$GameProcessId;hwnd=$sceneFocus.window;client=@(1600,900);crop=$sceneCrop;frames=$sceneFrames;nativePixels=$true} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $sceneOutput 'capture.json') -Encoding UTF8
    Write-Output ('BUILDER_SCENE_SEQUENCE ' + $sceneOutput)
}
