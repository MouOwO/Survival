param([int]$X,[int]$Y,[int]$Clicks=0,[int]$Wheel=0,[string]$Screenshot)
$ErrorActionPreference='Stop'
$evidenceName=$Screenshot
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
if($X -lt 0 -or $Y -lt 0 -or $X -ge $window.Width -or $Y -ge $window.Height){throw 'Outside test client'}
[void][HandoffWindow]::SetCursorPos($origin.X+$X,$origin.Y+$Y)
Start-Sleep -Milliseconds 450
for($i=0;$i -lt $Clicks;$i++){
 if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed; input cancelled'}
 [HandoffWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 120
 [HandoffWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 120
}
if($Wheel){if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed'};$delta=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Wheel),0);[HandoffWindow]::mouse_event(2048,0,0,$delta,[UIntPtr]::Zero)}
Start-Sleep -Milliseconds 900
if($evidenceName){
 if([IO.Path]::GetFileName($evidenceName) -ne $evidenceName){throw 'Filename required'}
 if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed; screenshot cancelled'}
 $bitmap=[Drawing.Bitmap]::new($window.Width,$window.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 try{$graphics.CopyFromScreen($origin.X,$origin.Y,0,0,$bitmap.Size);$folder=Join-Path $PSScriptRoot 'evidence';New-Item -ItemType Directory -Force $folder|Out-Null;$bitmap.Save((Join-Path $folder $evidenceName),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
}
