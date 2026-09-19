@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\map_c6\launch.ps1" -MapName template_map
if errorlevel 1 pause
