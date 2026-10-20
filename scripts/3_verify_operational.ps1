# ------------------------------------------------------------------------------
# 软件测试环境“正式可用性”全量自验脚本 (Verification Scorecard)
# ------------------------------------------------------------------------------
chcp 65001 >$null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$report = @()

function Test-Component($name, $category, $testScript) {
    try {
        $result = & $testScript
        if ($result.Success) {
            return [PSCustomObject]@{
                "测试组件" = $name
                "业务分类" = $category
                "测试结果" = "√ 正常可用"
                "详细运行信息" = $result.Message
            }
        } else {
            return [PSCustomObject]@{
                "测试组件" = $name
                "业务分类" = $category
                "测试结果" = "× 异常/未就绪"
                "详细运行信息" = $result.Message
            }
        }
    } catch {
        return [PSCustomObject]@{
            "测试组件" = $name
            "业务分类" = $category
            "测试结果" = "× 异常/失败"
            "详细运行信息" = $_.Exception.Message
        }
    }
}

# 1. Wireshark
$report += Test-Component "1. Wireshark" "抓包与底层协议" {
    $wsPaths = @("$env:ProgramFiles\Wireshark\Wireshark.exe", "D:\Wireshark\Wireshark.exe")
    foreach ($p in $wsPaths) {
        if (Test-Path $p) { return @{ Success = $true; Message = "二进制已就绪: $p" } }
    }
    return @{ Success = $false; Message = "未找到主程序" }
}

# 2. Apifox
$report += Test-Component "2. Apifox Desktop" "API 协同与调试" {
    $afPaths = @("$env:LOCALAPPDATA\Programs\apifox\Apifox.exe", "D:\Apifox\Apifox.exe", "$env:ProgramFiles\Apifox\Apifox.exe")
    foreach ($p in $afPaths) {
        if (Test-Path $p) { return @{ Success = $true; Message = "客户端就绪: $p" } }
    }
    return @{ Success = $false; Message = "未找到 Apifox 可执行文件" }
}

# 3. VS Code
$report += Test-Component "3. Visual Studio Code" "主开发与调试 IDE" {
    $c = Get-Command code -ErrorAction SilentlyContinue
    if ($c) {
        $v = code -v 2>&1 | Select-Object -First 1
        return @{ Success = $true; Message = "VS Code $v" }
    }
    return @{ Success = $false; Message = "未在系统 PATH 中找到 code" }
}

# 4. Git / Bash
$report += Test-Component "4. Git / Shell (Bash)" "命令行终端支撑" {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($g) {
        $gv = git --version
        return @{ Success = $true; Message = "$gv" }
    }
    return @{ Success = $false; Message = "未检测到 git 命令" }
}

# 5. PostgreSQL (文档矩阵: 由 Compose 容器提供，宿主安装仅作兼容)
$report += Test-Component "5. PostgreSQL 数据库" "数据持久化存储" {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $st = (docker ps --filter "name=qa-postgres" --format "{{.Status}}" 2>$null | Out-String).Trim()
        if ($st) { return @{ Success = $true; Message = "容器 qa-postgres: $st" } }
    }
    $svc = Get-Service | Where-Object { $_.Name -match "postgres" }
    if ($svc -and $svc.Status -eq "Running") {
        return @{ Success = $true; Message = "宿主机服务: $($svc.Name) (正在运行)" }
    }
    return @{ Success = $false; Message = "qa-postgres 容器未运行，宿主机也无运行中的 PostgreSQL" }
}

# 6. k6 压测引擎 (文档矩阵: 运行在容器内；宿主机安装仅作兼容)
$report += Test-Component "6. k6 性能压测" "高并发压测" {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $ver = (docker run --rm qa-runtime:local k6 version 2>&1 | Out-String).Trim()
        if ($ver -match "^k6 v") { return @{ Success = $true; Message = "$($ver.Split([Environment]::NewLine)[0]) (容器 qa-runtime:local)" } }
    }
    if (Get-Command k6 -ErrorAction SilentlyContinue) {
        $ver = (k6 version 2>&1 | Select-Object -First 1).Trim()
        return @{ Success = $true; Message = "$ver (宿主机)" }
    }
    return @{ Success = $false; Message = "容器镜像 qa-runtime:local 不存在，宿主机也未安装 k6" }
}

# 7. Playwright Web 端实际渲染测试
$report += Test-Component "7. Playwright (Web 自动化)" "端到端自动化" {
    $testPy = @"
from playwright.sync_api import sync_playwright
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto('https://example.com', timeout=10000)
        title = page.title()
        browser.close()
        print(f'SUCCESS: {title}')
except Exception as e:
    print(f'ERROR: {e}')
"@
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $res = docker run --rm qa-runtime:local python -c $testPy 2>$null
        if ($res -match "SUCCESS") {
            return @{ Success = $true; Message = "容器 Chromium 拉起并访问网页成功 ($res)" }
        }
    }
    $res = python -c $testPy 2>&1
    if ($res -match "SUCCESS") {
        return @{ Success = $true; Message = "宿主机 Chromium 拉起并访问网页成功 ($res)" }
    }
    return @{ Success = $false; Message = "容器与宿主机均未能启动 Chromium: $res" }
}

Write-Host "`n"
$report | Format-Table -AutoSize
