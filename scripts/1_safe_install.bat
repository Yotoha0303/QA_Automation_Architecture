@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title QA 测试环境 - 安装与校验
set "PS1=%~dp01_safe_install.ps1"

rem 无参数运行时可选择模式：(1) 显性安装 (2) 仅校验 (3) 仅装缺失 (4) 指定组件
rem 也可直接带参数运行，例如：1_safe_install.bat -VerifyOnly
if not "%~1"=="" (
    set "ARGS=%*"
    goto run
)

:menu
echo ========================================================
echo   QA 测试环境 - 安装与校验
echo ========================================================
echo    [1] 显性安装全部组件      (已存在则静默升级/覆盖)
echo    [2] 仅校验安装状态        (不安装，只报告是否装好)
echo    [3] 只安装缺失组件        (已存在的保持不动)
echo    [4] 显性安装指定组件      (如 apifox,k6)
echo    [0] 退出
echo --------------------------------------------------------
set "CHOICE="
set /p "CHOICE=请输入选项 [1]: "
if "!CHOICE!"=="" set "CHOICE=1"

if "!CHOICE!"=="0" goto end
if "!CHOICE!"=="1" (
    set "ARGS="
    goto run
)
if "!CHOICE!"=="2" (
    set "ARGS=-VerifyOnly"
    goto run
)
if "!CHOICE!"=="3" (
    set "ARGS=-InstallMissingOnly"
    goto run
)
if "!CHOICE!"=="4" (
    set "NAMES="
    set /p "NAMES=请输入组件关键字(逗号分隔，如 apifox,playwright,git): "
    if "!NAMES!"=="" (
        echo [!] 未输入关键字
        goto menu
    )
    set "ARGS=-Only !NAMES!"
    goto run
)
echo [!] 无效选项，请重新输入。
goto menu

:run
echo.
echo [*] 正在启动脚本... 参数: !ARGS!
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" !ARGS!
echo.
echo [*] 脚本已结束。校验结果: C:\Users\Yotoha\Desktop\Host_Baseline_Backup\verify_result.csv
pause
goto end

:end
endlocal
