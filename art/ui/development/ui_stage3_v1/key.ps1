param([ValidateSet('Escape','F1')][string]$Key='Escape')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed'}
$code=if($Key -eq 'Escape'){27}else{112}
[HandoffWindow]::keybd_event($code,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[HandoffWindow]::keybd_event($code,0,2,[UIntPtr]::Zero)
