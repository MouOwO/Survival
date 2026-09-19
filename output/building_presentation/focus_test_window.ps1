Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BuildingVisualWindow {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int n);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
    public static IntPtr GameWindow() { return FindWindow(null,"Dota 2"); }
}
'@
$buildingWindow=[BuildingVisualWindow]::GameWindow()
if ($buildingWindow -eq [IntPtr]::Zero) { throw 'Dota 2 window not found' }
$buildingWindowPid=0
[void][BuildingVisualWindow]::GetWindowThreadProcessId($buildingWindow,[ref]$buildingWindowPid)
if ((Get-Process -Id $buildingWindowPid).ProcessName -ne 'dota2') { throw 'Unexpected window process' }
[void][BuildingVisualWindow]::ShowWindow($buildingWindow,9)
[BuildingVisualWindow]::SetForegroundWindow($buildingWindow)
Start-Sleep -Milliseconds 1000
