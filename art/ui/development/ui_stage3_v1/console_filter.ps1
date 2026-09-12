param([string]$Filter='UI_STAGE3')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../remaining_ui_handoff_v1/console_input.ps1') -Command status -Inspect
if($Filter -notmatch '^[a-zA-Z0-9_]+$'){throw 'Only simple log filters'}
$vcRect=[HandoffWindow+Rect]::new();[void][HandoffWindow]::GetClientRect($vc.Handle,[ref]$vcRect)
$vcOrigin=[HandoffWindow+Point]::new();[void][HandoffWindow]::ClientToScreen($vc.Handle,[ref]$vcOrigin)
if([HandoffWindow]::GetForegroundWindow() -ne $vc.Handle){throw 'Focus changed'}
[void][HandoffWindow]::SetCursorPos($vcOrigin.X+400,$vcOrigin.Y+$vcRect.Bottom-118)
[HandoffWindow]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[HandoffWindow]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
[Windows.Forms.SendKeys]::SendWait('^a');[Windows.Forms.SendKeys]::SendWait($Filter)
Start-Sleep -Milliseconds 300
$bitmap=[Drawing.Bitmap]::new(1920,1080);$g=[Drawing.Graphics]::FromImage($bitmap)
try{$g.CopyFromScreen(0,0,0,0,$bitmap.Size);$bitmap.Save((Join-Path $PSScriptRoot ('evidence/console_'+$Filter+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$g.Dispose();$bitmap.Dispose()}
