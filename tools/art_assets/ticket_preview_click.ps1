param([int]$X,[int]$Y,[string]$Name)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class TicketPreviewMouse{[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr p);}'
[TicketPreviewMouse]::SetCursorPos($X,$Y)|Out-Null
[TicketPreviewMouse]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
[TicketPreviewMouse]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 800
Add-Type -AssemblyName System.Drawing
$b=New-Object Drawing.Bitmap(1920,1080);$g=[Drawing.Graphics]::FromImage($b)
try{$g.CopyFromScreen(0,0,0,0,$b.Size);$b.Save((Join-Path $PSScriptRoot ($Name+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$g.Dispose();$b.Dispose()}
