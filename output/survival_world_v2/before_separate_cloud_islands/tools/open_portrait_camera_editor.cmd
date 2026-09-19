@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0portrait_camera_editor.ps1"
if errorlevel 1 pause
