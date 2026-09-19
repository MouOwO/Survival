@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\open_scene.ps1" %*
pause
