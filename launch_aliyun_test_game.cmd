@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\launch_aliyun_test_game.ps1"
if errorlevel 1 (
    echo Test game connection failed. See the message above.
    pause
    exit /b 1
)
pause
