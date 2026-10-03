@echo off
setlocal
pushd "%~dp0"
title Repair archive texture dependencies
echo Close Dota 2 and Workshop Tools before running this repair.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\compile_archive_textures.ps1" -Repair
set "REPAIR_EXIT=%ERRORLEVEL%"
if not "%REPAIR_EXIT%"=="0" echo ARCHIVE_REPAIR_FAILED - Please keep the error above.
popd
pause
exit /b %REPAIR_EXIT%
