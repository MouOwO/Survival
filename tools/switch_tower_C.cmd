@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch_tower_preset.ps1" -Preset C
set "TOWER_SWITCH_EXIT=%ERRORLEVEL%"
if not defined TOWER_SWITCH_NO_PAUSE pause
exit /b %TOWER_SWITCH_EXIT%
