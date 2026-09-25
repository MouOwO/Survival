@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup_aliyun_test_host.ps1" %*
set "setup_result=%errorlevel%"
pause
exit /b %setup_result%
