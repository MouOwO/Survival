@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\join_lan_game.ps1" %*
set "join_result=%errorlevel%"
pause
exit /b %join_result%
