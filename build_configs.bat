@echo off
setlocal
chcp 65001 >nul
python "%~dp0tools\build_configs.py"
if errorlevel 1 (
  echo CONFIG_BUILD_FAILED
  exit /b 1
)
echo CONFIG_BUILD_PASS
endlocal
