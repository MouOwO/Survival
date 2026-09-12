param([Parameter(Mandatory=$true)][string]$Command,[switch]$Inspect)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1')
$consoleIds=@(Get-Process vconsole2 -ErrorAction Stop | ForEach-Object {$_.Id})
$script:consoleWindows=@()
[HandoffWindow]::EnumWindows({param($handle,$arg)
 $owner=0;[void][HandoffWindow]::GetWindowThreadProcessId($handle,[ref]$owner)
 if($consoleIds -contains $owner){$title=[Text.StringBuilder]::new(512);[void][HandoffWindow]::GetWindowText($handle,$title,512);if($title.ToString() -like '*VConsole*'){$script:consoleWindows+=@{Handle=$handle;Title=$title.ToString()}}}
 return $true
},[IntPtr]::Zero)|Out-Null
$vc=$consoleWindows|Where-Object {$_.Title -eq 'VConsole2 (64-bit)'}|Select-Object -First 1
foreach($popup in $consoleWindows){if($popup.Title -eq 'vconsole2'){[void][HandoffWindow]::ShowWindow($popup.Handle,0)}}
if(-not $vc){throw 'Existing VConsole window not found'}
[void][HandoffWindow]::ShowWindow($vc.Handle,9);[void][HandoffWindow]::SetForegroundWindow($vc.Handle);Start-Sleep -Milliseconds 250
if([HandoffWindow]::GetForegroundWindow() -ne $vc.Handle){throw 'VConsole is not foreground'}
if($Inspect){$bitmap=[Drawing.Bitmap]::new(1920,1080);$g=[Drawing.Graphics]::FromImage($bitmap);try{$g.CopyFromScreen(0,0,0,0,$bitmap.Size);$bitmap.Save((Join-Path $PSScriptRoot 'console_inspect.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$g.Dispose();$bitmap.Dispose()};return}
if($Command -notmatch '^[a-zA-Z0-9_ .-]+$'){throw 'Only explicit ASCII engine commands are supported'}
$vcRect=[HandoffWindow+Rect]::new();[void][HandoffWindow]::GetClientRect($vc.Handle,[ref]$vcRect)
$vcOrigin=[HandoffWindow+Point]::new();[void][HandoffWindow]::ClientToScreen($vc.Handle,[ref]$vcOrigin)
[void][HandoffWindow]::SetCursorPos($vcOrigin.X+400,$vcOrigin.Y+$vcRect.Bottom-53);[HandoffWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[HandoffWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
[Windows.Forms.SendKeys]::SendWait('^a');[Windows.Forms.SendKeys]::SendWait($Command)
Start-Sleep -Milliseconds 200
[HandoffWindow]::keybd_event(13,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 120
[HandoffWindow]::keybd_event(13,0,2,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 300
