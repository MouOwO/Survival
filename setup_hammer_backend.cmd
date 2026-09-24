@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup_hammer_backend.ps1" -Action Install
if errorlevel 1 (
    echo Hammer backend setup failed. See the message above.
    pause
    exit /b 1
)
pause
