@echo off
chcp 65001 >nul
setlocal
pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\account_cleanup\launch.ps1"
set "CLEANUP_EXIT=%ERRORLEVEL%"
popd
pause
exit /b %CLEANUP_EXIT%
