param([Parameter(Mandatory=$true)][ValidateSet('-rogue recruit_training tower_growth frozen_wall')][string]$Command)
$ErrorActionPreference='Stop'
$testCommand=$Command
. (Join-Path $PSScriptRoot '../ui_handoff_v1/game_window.ps1') -Show
if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Not the isolated test game'}
[Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Milliseconds 150
if([HandoffWindow]::GetForegroundWindow() -ne $window.Handle){throw 'Focus changed'}
[Windows.Forms.SendKeys]::SendWait($testCommand)
[Windows.Forms.SendKeys]::SendWait('{ENTER}')
