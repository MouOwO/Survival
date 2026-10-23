@echo off
chcp 65001 >nul
if not exist "%~dp0collect_join_network.ps1" (
  echo network_collector_missing
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_join_network.ps1" %*
set "WS4_NETWORK_RESULT=%ERRORLEVEL%"
echo.
echo Please send join_network_diagnostic.json to the author.
pause
exit /b %WS4_NETWORK_RESULT%
