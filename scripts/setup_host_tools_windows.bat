@echo off
chcp 65001 >nul
title QA Automation Host Tools Installer
echo ========================================================
echo   Launching Windows Host Tools Installer...
echo   (Bypassing PowerShell ExecutionPolicy automatically)
echo ========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_host_tools_windows.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Process exited with code %errorlevel%
)
pause
