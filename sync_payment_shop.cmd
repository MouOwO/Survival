@echo off
setlocal
pushd "%~dp0"
title Sync game shop CSV
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\sync_payment_shop.ps1" %*
set "SHOP_EXIT=%ERRORLEVEL%"
if not "%SHOP_EXIT%"=="0" echo SHOP_SYNC_FAILED - Please keep the error above.
popd
pause
exit /b %SHOP_EXIT%
