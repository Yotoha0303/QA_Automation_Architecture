@echo off
chcp 65001 >nul
title Mobile Hybrid Architecture - Host ADB Server
echo ========================================================
echo   Mobile Hybrid Architecture: Host ADB Server
echo ========================================================
echo Stopping existing adb server...
adb kill-server

echo Starting ADB Server on 0.0.0.0:5037...
echo Inside Docker container: use host.docker.internal:5037
echo.
adb -a nodaemon server start
pause
