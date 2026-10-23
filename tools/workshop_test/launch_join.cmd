@echo off
setlocal
chcp 65001 >nul
title Survival WS4 - Join game
echo Survival WS4 - Guest launcher
echo Keep Steam and Radmin VPN online before joining the host.
echo.
if not exist "%~dp0join_client.ps1" goto missing_files
for %%F in ("%~dp0join_client.ps1") do if %%~zF EQU 0 goto missing_files
if not exist "%~dp0client_manifest.json" goto missing_files
for %%F in ("%~dp0client_manifest.json") do if %%~zF EQU 0 goto missing_files
if not exist "%~dp0survival_ws4_local\addoninfo.txt" goto missing_files
echo Checking the complete client package. Please keep this window open.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0join_client.ps1" %*
set "ws4_join_result=%errorlevel%"
if "%ws4_join_result%"=="0" exit /b 0
echo.
echo Join preparation failed. Please send the error shown above to the author.
pause
exit /b %ws4_join_result%

:missing_files
echo [WS4] guest_files_missing_or_empty
echo Extract the FULL client ZIP first. Do not run this file inside a ZIP viewer.
echo Keep this CMD beside join_client.ps1, client_manifest.json and survival_ws4_local.
echo A Git checkout or the launcher repair ZIP alone does not contain the game assets.
pause
exit /b 1
