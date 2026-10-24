@echo off
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\workshop_test\launch_test.ps1" -Mode Online %*
if errorlevel 1 pause
