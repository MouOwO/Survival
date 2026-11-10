@echo off
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\workshop_test\launch_published.ps1" %*
if errorlevel 1 pause
