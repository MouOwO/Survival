@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\launch_aliyun_lan_host.ps1" %*
set "lan_result=%errorlevel%"
pause
exit /b %lan_result%
