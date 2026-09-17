param([Parameter(Mandatory=$true)][string]$Command)
$ErrorActionPreference='Stop'
if($Command -notmatch '^-(dev|shopshow|addhero|choujiang [0-9]+|rogue [a-z_]+ [a-z_]+ [a-z_]+)$'){throw 'Not an approved existing UI test command'}
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed'}
[HandoffWindow]::keybd_event(13,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[HandoffWindow]::keybd_event(13,0,2,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 250
[Windows.Forms.SendKeys]::SendWait($Command)
Start-Sleep -Milliseconds 180
[HandoffWindow]::keybd_event(13,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[HandoffWindow]::keybd_event(13,0,2,[UIntPtr]::Zero)
