@echo off
start "" /b powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0tools\release_packager.ps1" -Action gui
