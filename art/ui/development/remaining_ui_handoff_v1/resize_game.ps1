param([int]$Width=1280,[int]$Height=720,[switch]$Restore)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
Add-Type @'
using System;using System.Runtime.InteropServices;
public class HandoffResize {
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
 public struct R {public int Left,Top,Right,Bottom;}
}
'@
$saved=Join-Path $PSScriptRoot 'game_window_original.json'
$r=[HandoffResize+R]::new();[void][HandoffResize]::GetWindowRect($window.Handle,[ref]$r)
if($Restore){
 $s=Get-Content -LiteralPath $saved -Raw|ConvertFrom-Json
 if($s.processId -ne $game.Id){throw 'Game process changed; refusing stale window restore'}
 [void][HandoffResize]::SetWindowPos($window.Handle,[IntPtr]::Zero,$s.x,$s.y,$s.width,$s.height,4)
}else{
 if($Width -lt 1000 -or $Width -gt 1920 -or $Height -lt 600 -or $Height -gt 1080){throw 'Unsupported test size'}
 if(-not(Test-Path -LiteralPath $saved)){@{processId=$game.Id;x=$r.Left;y=$r.Top;width=$r.Right-$r.Left;height=$r.Bottom-$r.Top;clientWidth=$window.Width;clientHeight=$window.Height}|ConvertTo-Json|Set-Content -LiteralPath $saved -Encoding utf8}
 $outerWidth=$Width+($r.Right-$r.Left-$window.Width);$outerHeight=$Height+($r.Bottom-$r.Top-$window.Height)
 [void][HandoffResize]::SetWindowPos($window.Handle,[IntPtr]::Zero,$r.Left,$r.Top,$outerWidth,$outerHeight,4)
}
Start-Sleep -Milliseconds 1200
$client=[HandoffWindow+Rect]::new();[void][HandoffWindow]::GetClientRect($window.Handle,[ref]$client)
@{clientWidth=$client.Right;clientHeight=$client.Bottom;restored=[bool]$Restore}|ConvertTo-Json
