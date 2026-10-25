@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\launch_offline_onboarding_test.ps1"
if errorlevel 1 pause
