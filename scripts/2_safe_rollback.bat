@echo off
chcp 65001 >nul
title 宿主一键完全复原
echo ========================================================
echo   正在启动宿主完全复原程序...
echo   (安全卸载测试软件，还原环境变量，绝不碰已有系统)
echo ========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp02_safe_rollback.ps1"
pause
