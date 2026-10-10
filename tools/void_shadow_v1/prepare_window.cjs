'use strict';
const fs=require('fs');
let s=fs.readFileSync('tools/map_c6/window.ps1','utf8');
s=s.replace('[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);',`[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool attach);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();`);
const old='if($Show){[void][HandoffWindow]::ShowWindow($window.Handle,9);[void][HandoffWindow]::SetForegroundWindow($window.Handle);Start-Sleep -Milliseconds 750}';
if(!s.includes(old))throw Error('Missing verified window activation anchor');
s=s.replace(old,`if($Show){
    [void][HandoffWindow]::ShowWindow($window.Handle,9)
    $voidForeground=[HandoffWindow]::GetForegroundWindow()
    $voidOwner=0
    $voidThread=[HandoffWindow]::GetWindowThreadProcessId($voidForeground,[ref]$voidOwner)
    $voidCurrent=[HandoffWindow]::GetCurrentThreadId()
    $voidAttached=$false
    try {
        if($voidThread -ne $voidCurrent){$voidAttached=[HandoffWindow]::AttachThreadInput($voidCurrent,$voidThread,$true)}
        [void][HandoffWindow]::BringWindowToTop($window.Handle)
        [void][HandoffWindow]::SetForegroundWindow($window.Handle)
    } finally {if($voidAttached){[void][HandoffWindow]::AttachThreadInput($voidCurrent,$voidThread,$false)}}
    Start-Sleep -Milliseconds 750
}`);
// Keep the existing ToolsMode/map identity and foreground guards; only outputs differ.
s=s.replace("$folder=Join-Path $PSScriptRoot '../../output/map_build_c6'","$folder=Join-Path $PSScriptRoot '../../design_refs/void_shadow_v1/work/native'");
fs.writeFileSync('tools/void_shadow_v1/window.ps1',s);
