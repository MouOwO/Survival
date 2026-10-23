@echo off
setlocal
chcp 65001 >nul
title Survival WS4 - Check all client resources
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0join_client.ps1" -CheckOnly -AuditAll
set "ws4_audit_result=%errorlevel%"
echo.
echo The resource audit does not start Dota or connect to the host.
echo Please send client_resource_audit.json to the author if problems remain.
pause
exit /b %ws4_audit_result%
