@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\map_c6\launch-valley-review.ps1"
if errorlevel 1 pause
