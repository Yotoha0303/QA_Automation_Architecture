<#
================================================================================
  QA 现代化自动化测试工程 - Windows 环境清理与生命周期闭环脚本 (clean.ps1)
  实现测试机环境“随开随用、用完即净”的完整生命周期管理：
    1. 停止并清理全部 QA 容器 (qa-postgres, qa-mock-service, qa-test-runner, qa-allure, qa-appium)
    2. 清理容器专用网桥网络 (qa-infra-net)
    3. 清理测试结果与运行缓存 (allure-results, allure-reports, .pytest_cache, __pycache__)
    4. 停止宿主后台 ADB Server (释放 5037 端口)
    5. 可选清理数据卷 (PostgreSQL 数据库重置出厂) 与本地镜像
================================================================================
  参数:
    -Volumes / -v    同时清除 Docker 数据卷 (PostgreSQL 测试数据完全重置)
    -Images / -i     同时清除本地运行时镜像 (qa-runtime:local)
    -All / -a        彻底清理: 容器 + 数据卷 + 镜像 + 所有测试缓存
    -KeepResults     保留 allure-results 目录中的测试数据，不删除
    -KeepAdb         保留宿主 ADB 后台服务，不执行 adb kill-server
================================================================================
#>
chcp 65001 >$null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$CleanVolumes = $false
$CleanImages  = $false
$KeepResults  = $false
$KeepAdb      = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^(-Volumes|-v)$'     { $CleanVolumes = $true }
        '^(-Images|-i)$'      { $CleanImages  = $true }
        '^(-All|-a)$'         { $CleanVolumes = $true; $CleanImages = $true }
        '^-KeepResults$'      { $KeepResults  = $true }
        '^-KeepAdb$'          { $KeepAdb      = $true }
    }
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $ProjectRoot "docker-compose.infra.yml"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    [√] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "    [×] $msg" -ForegroundColor Red }

Write-Host "================================================================================" -ForegroundColor DarkCyan
Write-Host "       QA Automation Architecture - Windows 环境清理与生命周期闭环" -ForegroundColor DarkCyan
Write-Host "       (随开随用、用完即净：容器关闭、端口释放、缓存清理)" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor DarkCyan

# 1. 停止并移除 Docker 容器与网络
Step "停止并移除 Docker 容器与基础设施..."
if (Get-Command docker -ErrorAction SilentlyContinue) {
    if ($CleanVolumes) {
        Write-Host "    执行 docker compose down -v (包含数据卷清理)..." -ForegroundColor Yellow
        docker compose -f "$ComposeFile" down -v --remove-orphans
    } else {
        docker compose -f "$ComposeFile" down --remove-orphans
    }
    if ($LASTEXITCODE -eq 0) {
        OK "所有 QA 容器与专属网桥网络已停止并释放"
    } else {
        Warn "docker compose down 执行返回非零，可能有容器已被手动清理"
    }

    if ($CleanImages) {
        Step "清理本地测试运行时镜像 (qa-runtime:local)..."
        docker rmi qa-runtime:local -f 2>$null
        OK "已清理 qa-runtime:local 本地镜像"
    }
} else {
    Warn "未检测到 docker 命令，跳过容器清理"
}

# 2. 停止宿主 ADB 5037 后台监听
if (-not $KeepAdb) {
    Step "检查并释放宿主 ADB Server (5037 端口)..."
    $adbCmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($adbCmd) {
        & adb kill-server 2>&1 | Out-Null
        OK "已释放宿主 ADB Server (5037 端口已关闭)"
    } else {
        OK "未检测到宿主 adb 进程"
    }
} else {
    Warn "已保留宿主 ADB 服务 (-KeepAdb)"
}

# 3. 清理测试结果与运行时缓存目录
Step "清理测试结果与框架运行时缓存..."
$cleanDirs = @(
    (Join-Path $ProjectRoot ".pytest_cache"),
    (Join-Path $ProjectRoot "test-results"),
    (Join-Path $ProjectRoot "playwright-report"),
    (Join-Path $ProjectRoot "blob-report")
)

if (-not $KeepResults) {
    $cleanDirs += (Join-Path $ProjectRoot "allure-results")
    $cleanDirs += (Join-Path $ProjectRoot "allure-reports")
}

foreach ($d in $cleanDirs) {
    if (Test-Path $d) {
        Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue
        OK "已清理目录: $(Split-Path $d -Leaf)"
    }
}

# 清理 Python __pycache__ 目录
Get-ChildItem -Path $ProjectRoot -Filter "__pycache__" -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
OK "已递归清理 Python __pycache__ 缓存"

# 4. 清理网络探测缓存文件
$netCache = Join-Path $ProjectRoot ".qa_network_profile"
if (Test-Path $netCache) { Remove-Item -Path $netCache -Force -ErrorAction SilentlyContinue }

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "【环境清理完成】测试环境已完全复原，端口已释放，达到“用完即净”标准！" -ForegroundColor Green
Write-Host "  * 下次拉起环境: 直接双击 start.bat 或运行 powershell .\scripts\start.ps1" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Green
