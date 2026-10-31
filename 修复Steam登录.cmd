@echo off
chcp 65001 >nul
setlocal
pushd "%~dp0"
if errorlevel 1 exit /b 1
set "STEAM_LOGIN_REPAIR_PYTHON=%LocalAppData%\Programs\Python\Python314\python.exe"
if exist "%STEAM_LOGIN_REPAIR_PYTHON%" goto run_local_python
where py >nul 2>nul
if errorlevel 1 goto python_missing
py -3 -B -X utf8 "tools\workshop_test\repair_steam_login.py" --repair
goto finished
:run_local_python
"%STEAM_LOGIN_REPAIR_PYTHON%" -B -X utf8 "tools\workshop_test\repair_steam_login.py" --repair
goto finished
:python_missing
echo 未找到 Python。请联系维护者检查本机工具环境。
cmd /c exit 1
:finished
set "STEAM_LOGIN_REPAIR_EXIT=%errorlevel%"
echo.
pause
popd
exit /b %STEAM_LOGIN_REPAIR_EXIT%
