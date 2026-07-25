@echo off
setlocal
cd /d "%~dp0"
title RB MCreator Version Updater
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Convert-ToNeoForge262-GUI.ps1"
if errorlevel 1 pause
endlocal
