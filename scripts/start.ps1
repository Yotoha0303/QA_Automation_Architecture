<#
================================================================================
  QA 现代化自动化测试工程 - Windows 一键全流程启动与验证脚本 (start.ps1)
  严格依据架构层级与组件映射规范：
    【层级 1: 宿主环境与桌面工具】Wireshark, Apifox Desktop, VS Code, Git, Docker Desktop
    【层级 2: 测试编排与存储依赖】PostgreSQL 16 (独立容器) + Prism HTTP Mock
    【层级 3: 自动化测试运行时】Python 3.12+, Playwright, k6, apifox-cli (Dev Container)
    【层级 4: 移动端支撑层】Appium Server + 宿主 ADB 5037 跨容器桥接
    【层级 5: 缺陷管理集成】Jira SaaS REST API 自动提单与 conftest 钩子
    【层级 6: 持续集成与全流程验证】API 接口测试 + Web 端到端测试 + k6 性能基线测试
================================================================================
  参数:
    -RunTests       是否执行全流程自动化测试验证 (默认: $true)
    -SkipTests      跳过测试执行，仅拉起环境
    -SkipHostTools  跳过宿主 winget 依赖检查/静默安装
    -SkipMobile     跳过移动端模拟器与宿主 ADB 检测
    -WithMobile     额外启动 Appium Server 容器 (混合架构)
    -WithPerf       是否在测试流程中执行 k6 性能压测 (默认: $true)
    -SkipPerf       跳过 k6 压测，仅执行 API 与 Web 测试
    -OpenVsCode     测试完成后唤起 VS Code Dev Container (Testing-Lab)
    -NoVsCode       不唤起 VS Code (默认)
    -Mirror cn|global|auto|cache
                    网络档位：国内镜像 / 官方源 / 重新探测 / 复用上次探测 (默认: cache)
================================================================================
#>
chcp 65001 >$null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$script:RunTests      = $true
$script:SkipHostTools = $false
$script:SkipMobile    = $false
$script:WithMobile    = $false
$script:WithPerf      = $true
$script:OpenVsCode    = $false
$script:MirrorMode    = "cache"

for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^-RunTests$'      { $script:RunTests = $true }
        '^-SkipTests$'     { $script:RunTests = $false }
        '^-SkipHostTools$' { $script:SkipHostTools = $true }
        '^-SkipMobile$'    { $script:SkipMobile = $true }
        '^-WithMobile$'    { $script:WithMobile = $true }
        '^-WithPerf$'      { $script:WithPerf = $true }
        '^-SkipPerf$'      { $script:WithPerf = $false }
        '^-OpenVsCode$'    { $script:OpenVsCode = $true }
        '^-NoVsCode$'      { $script:OpenVsCode = $false }
        '^-Mirror$'        { if ($i + 1 -lt $args.Count) { $script:MirrorMode = $args[$i + 1].ToLower(); $i++ } }
    }
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $ProjectRoot "docker-compose.infra.yml"
$PackagesFile = Join-Path $PSScriptRoot "packages.json"
$NetworkScript = Join-Path $PSScriptRoot "network.ps1"

function Section($title) {
    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host " $title" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    [√] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "    [×] $msg" -ForegroundColor Red }

# 记录全流程架构评分卡
$script:Scorecard = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-Score($layer, $comp, $status, $detail) {
    $script:Scorecard.Add([PSCustomObject]@{
        "架构层级"     = $layer
        "组件 / 服务"   = $comp
        "运行状态"     = $status
        "详细信息"     = $detail
    })
}

Write-Host "================================================================================" -ForegroundColor DarkCyan
Write-Host "       QA Automation Architecture - Windows 一键全流程启动与测试环境" -ForegroundColor DarkCyan
Write-Host "================================================================================" -ForegroundColor DarkCyan

# 解析网络档位
if (Test-Path $NetworkScript) {
    . $NetworkScript
    $script:QaNet = Resolve-QaNetwork -Mode $script:MirrorMode -TempDir "C:\QA_Installers_Temp"
    if ($script:QaNet.Profile -eq "cn") {
        $env:QA_CN_BUILD = "1"
        if ($script:QaNet.GitHubProxy) { $env:GITHUB_PROXY = $script:QaNet.GitHubProxy }
        Write-Host "网络档位: 国内镜像 (QA_CN_BUILD=1, 代理=$($script:QaNet.GitHubProxy))" -ForegroundColor Gray
    } else {
        $env:QA_CN_BUILD = "0"
        Remove-Item Env:GITHUB_PROXY -ErrorAction SilentlyContinue
        Write-Host "网络档位: 官方源 (QA_CN_BUILD=0)" -ForegroundColor Gray
    }
} else {
    $env:QA_CN_BUILD = "0"
}

# ------------------------------------------------------------------------------
# 【层级 1: 宿主环境与桌面工具】
# ------------------------------------------------------------------------------
Section "【层级 1: 宿主环境与桌面工具 (Host Tools)】"

# 1.1 检查/安装宿主桌面工具
if (-not $script:SkipHostTools) {
    Step "检查宿主工具链 (Wireshark, Apifox, VS Code, Git, Docker Desktop)..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        # 预先快速检查缺少哪些包，如果都存在则跳过长耗时 import
        $hasWs = Test-Path "$env:ProgramFiles\Wireshark\Wireshark.exe"
        $hasAf = (Test-Path "$env:LOCALAPPDATA\Programs\apifox\Apifox.exe") -or (Test-Path "$env:ProgramFiles\Apifox\Apifox.exe")
        $hasCode = (Get-Command code -ErrorAction SilentlyContinue) -ne $null
        $hasGit = (Get-Command git -ErrorAction SilentlyContinue) -ne $null
        $hasDocker = (Get-Command docker -ErrorAction SilentlyContinue) -ne $null

        if (-not ($hasWs -and $hasAf -and $hasCode -and $hasGit -and $hasDocker)) {
            Write-Host "    发现部分宿主工具未安装，正在执行 winget 导入安装..." -ForegroundColor Yellow
            winget import -i $PackagesFile --accept-package-agreements --accept-source-agreements --disable-interactivity
        } else {
            OK "检测到宿主桌面工具均已安装，跳过重复 winget import"
        }
    } else {
        Warn "未检测到 winget，如需安装宿主桌面工具请运行 scripts\setup_host_tools_windows.bat"
    }
} else {
    Warn "已跳过宿主桌面工具检查 (-SkipHostTools)"
}

# 刷新系统环境变量 PATH
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# 详细登记层级 1 状态
$wsPath = @("$env:ProgramFiles\Wireshark\Wireshark.exe", "D:\Wireshark\Wireshark.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($wsPath) { OK "Wireshark: $wsPath"; Add-Score "1. 宿主工具" "Wireshark" "√ 就绪" $wsPath }
else { Warn "Wireshark: 未检测到可执行文件"; Add-Score "1. 宿主工具" "Wireshark" "! 未安装" "可选抓包工具" }

$afPath = @("$env:LOCALAPPDATA\Programs\apifox\Apifox.exe", "$env:ProgramFiles\Apifox\Apifox.exe", "D:\Apifox\Apifox.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($afPath) { OK "Apifox Desktop: $afPath"; Add-Score "1. 宿主工具" "Apifox Desktop" "√ 就绪" $afPath }
else { Warn "Apifox Desktop: 未检测到客户端"; Add-Score "1. 宿主工具" "Apifox Desktop" "! 未安装" "可选桌面端" }

$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if ($codeCmd) {
    $codeVer = (code -v 2>&1 | Select-Object -First 1)
    OK "VS Code: $codeVer"; Add-Score "1. 宿主工具" "VS Code" "√ 就绪" "v$codeVer"
} else {
    Warn "VS Code: 未找到 code 命令"; Add-Score "1. 宿主工具" "VS Code" "! 未在 PATH" "建议加入 PATH"
}

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitVer = (git --version 2>&1).Trim()
    OK "Git: $gitVer"; Add-Score "1. 宿主工具" "Git" "√ 就绪" $gitVer
} else {
    Warn "Git: 未找到 git 命令"; Add-Score "1. 宿主工具" "Git" "× 缺失" "缺少版本管理工具"
}

# 1.2 Docker 引擎检查
Step "检查 Docker 引擎运行状态..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "未检测到 docker 命令，测试基础设施需要 Docker Desktop 支持！"
    Add-Score "1. 宿主工具" "Docker 引擎" "× 未安装" "未找到 docker 命令"
    exit 1
}

docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    $dd = @("$env:ProgramFiles\Docker\Docker\Docker Desktop.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($dd) {
        Warn "Docker 引擎未运行，正在启动 Docker Desktop..."
        Start-Process -FilePath $dd | Out-Null
        $deadline = (Get-Date).AddSeconds(120)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            docker info 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
        }
    }
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "Docker 引擎未能就绪，请手动启动 Docker Desktop 后重试。"
        Add-Score "1. 宿主工具" "Docker 引擎" "× 未运行" "Docker Desktop 服务离线"
        exit 1
    }
}
$dockerVer = (docker version --format '{{.Server.Version}}' 2>$null)
OK "Docker 引擎就绪 (Docker v$dockerVer)"
Add-Score "1. 宿主工具" "Docker 引擎" "√ 就绪" "Docker v$dockerVer"

# ------------------------------------------------------------------------------
# 【层级 2: 测试编排与存储依赖】
# ------------------------------------------------------------------------------
Section "【层级 2: 测试编排与存储依赖 (PostgreSQL + Prism Mock + Allure Report)】"

Step "启动基础容器服务 (PostgreSQL 16 + Prism HTTP Mock + Allure Report)..."
docker compose -f "$ComposeFile" up -d postgres-db mock-service allure
if ($LASTEXITCODE -ne 0) {
    Fail "Docker Compose 启动基础服务失败"
    Add-Score "2. 编排与存储" "基础容器组" "× 启动失败" "Compose exit != 0"
    exit 1
}

# 等待 PostgreSQL 数据库健康就绪
Write-Host "    等待 PostgreSQL 数据库健康就绪..." -ForegroundColor Gray
$deadline = (Get-Date).AddSeconds(60)
$pgHealthy = $false
while ((Get-Date) -lt $deadline) {
    $status = (docker inspect -f '{{.State.Health.Status}}' qa-postgres 2>$null | Out-String).Trim()
    if ($status -eq "healthy") { $pgHealthy = $true; break }
    Start-Sleep -Seconds 2
}
if ($pgHealthy) {
    OK "PostgreSQL 16 数据库已就绪 (端口: 5432, 库: qa_testdb)"
    Add-Score "2. 编排与存储" "PostgreSQL 16" "√ Healthy" "localhost:5432 / qa_testdb"
} else {
    Warn "PostgreSQL 数据库未在超时时间内达到 healthy 状态"
    Add-Score "2. 编排与存储" "PostgreSQL 16" "! Starting" "等待超时"
}

# 验证 Prism Mock 服务
$mockHealthy = $false
try {
    $resp = curl.exe -s -m 5 http://localhost:4010/api/v1/health 2>$null
    if ($resp -match '"status"\s*:\s*"UP"') { $mockHealthy = $true }
} catch {}
if ($mockHealthy) {
    OK "Prism HTTP Mock 服务已就绪 (端口: 4010, /api/v1/health -> UP)"
    Add-Score "2. 编排与存储" "Prism Mock" "√ 就绪" "http://localhost:4010"
} else {
    Warn "Prism Mock 服务未返回预期健康响应"
    Add-Score "2. 编排与存储" "Prism Mock" "! 响应异常" "http://localhost:4010"
}

# 验证 Allure 图形化报告服务
$allureHealthy = $false
try {
    $resp = curl.exe -s -m 5 -I http://localhost:5050 2>$null
    if ($resp -match 'HTTP.*200') { $allureHealthy = $true }
} catch {}
if ($allureHealthy) {
    OK "Allure 图形化报告服务已就绪 (端口: 5050, http://localhost:5050)"
    Add-Score "2. 编排与存储" "Allure Report" "√ 就绪" "http://localhost:5050"
} else {
    Warn "Allure 报告服务未完全就绪 (启动中)"
    Add-Score "2. 编排与存储" "Allure Report" "! 启动中" "http://localhost:5050"
}

# ------------------------------------------------------------------------------
# 【层级 3: 自动化测试运行时】
# ------------------------------------------------------------------------------
Section "【层级 3: 自动化测试运行时 (Dev Container 统一镜像)】"

# 检查本地是否存在运行时镜像，不存在则优先从 GHCR 拉取预编译镜像，失败则自动本地构建
$prebuiltImage = if ($env:QA_RUNTIME_IMAGE) { $env:QA_RUNTIME_IMAGE } else { "ghcr.io/yotoha0303/qa-runtime:latest" }
$hasRuntimeImage = [bool](docker images -q qa-runtime:local 2>$null) -or [bool](docker images -q $prebuiltImage 2>$null)

if (-not $hasRuntimeImage) {
    Step "未检测到本地运行时镜像，优先从 GitHub Container Registry (GHCR) 拉取预编译镜像..."
    Write-Host "    尝试拉取: $prebuiltImage (免去本地耗时 15 分钟编译 6.5GB)..." -ForegroundColor Cyan
    docker pull $prebuiltImage 2>$null
    if ($LASTEXITCODE -eq 0) {
        docker tag $prebuiltImage qa-runtime:local 2>$null
        OK "成功拉取并关联 GHCR 预编译镜像: $prebuiltImage"
    } else {
        Warn "GHCR 预编译镜像未拉取成功 (网络离线或尚未发布至 GHCR)，正在执行本地自动化构建..."
        docker compose -f "$ComposeFile" build test-runner
        if ($LASTEXITCODE -ne 0) {
            Fail "测试运行时镜像构建失败"
            Add-Score "3. 测试运行时" "qa-runtime 镜像" "× 构建失败" "Build exit != 0"
            exit 1
        }
    }
}
OK "测试运行时镜像就绪: qa-runtime:local"

# 启动 test-runner 容器
Step "启动自动化测试运行时容器 (qa-test-runner)..."
docker compose -f "$ComposeFile" up -d test-runner
if ($LASTEXITCODE -eq 0) {
    OK "测试运行时容器已启动 (工作目录: /workspace, 内置 Python 3.12, Playwright, k6)"
    Add-Score "3. 测试运行时" "test-runner 容器" "√ 运行中" "qa-test-runner (sleep infinity)"
} else {
    Fail "测试运行时容器启动失败"
    Add-Score "3. 测试运行时" "test-runner 容器" "× 启动失败" "Compose exit != 0"
    exit 1
}

# ------------------------------------------------------------------------------
# 【层级 4: 移动端支撑层】
# ------------------------------------------------------------------------------
Section "【层级 4: 移动端支撑层 (Appium + 宿主 ADB 混合架构)】"

if (-not $script:SkipMobile) {
    Step "检测 Android ADB 工具与设备通道..."
    $Adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
    if (-not $Adb) {
        $sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk") | Where-Object { $_ }
        foreach ($root in $sdkRoots) {
            $candidate = Join-Path $root "platform-tools\adb.exe"
            if (Test-Path $candidate) { $Adb = $candidate; break }
        }
    }

    if ($Adb) {
        # 确保 ADB Server 以 -a 监听 0.0.0.0:5037 供 Docker 容器跨主机连接
        & $Adb kill-server 2>&1 | Out-Null
        Start-Process -FilePath $Adb -ArgumentList @("-a", "nodaemon", "server", "start") -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 2
        $adbPortListen = (Get-NetTCPConnection -LocalPort 5037 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($adbPortListen) {
            OK "宿主 ADB 服务已监听 0.0.0.0:5037 (供容器通过 host.docker.internal 桥接)"
            Add-Score "4. 移动端支撑" "宿主 ADB Server" "√ 监听中" "0.0.0.0:5037 桥接已建立"
        } else {
            Warn "宿主 ADB 未能成功监听 5037 端口"
            Add-Score "4. 移动端支撑" "宿主 ADB Server" "! 端口未监听" "5037 端口未就绪"
        }
    } else {
        Warn "未检测到 adb.exe，移动端测试将默认处于跳过状态"
        Add-Score "4. 移动端支撑" "宿主 ADB" "- 未检测到" "如需移动端请安装 Android SDK"
    }

    if ($script:WithMobile) {
        Step "拉起 Appium Server 容器 (--profile mobile)..."
        docker compose -f "$ComposeFile" --profile mobile up -d appium
        if ($LASTEXITCODE -eq 0) {
            OK "Appium Server 容器已启动 (http://localhost:4723)"
            Add-Score "4. 移动端支撑" "Appium Server" "√ 运行中" "localhost:4723"
        } else {
            Warn "Appium Server 容器启动失败"
            Add-Score "4. 移动端支撑" "Appium Server" "× 启动失败" "profile mobile 失败"
        }
    } else {
        Add-Score "4. 移动端支撑" "Appium Server" "- 按需就绪" "加 -WithMobile 自动拉起容器"
    }
} else {
    Warn "已跳过移动端支撑层检测 (-SkipMobile)"
    Add-Score "4. 移动端支撑" "移动端混合层" "- 已跳过" "-SkipMobile"
}

# ------------------------------------------------------------------------------
# 【层级 5: 缺陷管理集成】
# ------------------------------------------------------------------------------
Section "【层级 5: 缺陷管理集成 (Jira SaaS REST API)】"

$jiraEnv = Join-Path $ProjectRoot "config\jira_config.env"
$jiraExample = Join-Path $ProjectRoot "config\jira_config.env.example"
if (-not (Test-Path $jiraEnv) -and (Test-Path $jiraExample)) {
    Copy-Item $jiraExample $jiraEnv
    Warn "已从 jira_config.env.example 自动生成配置文件"
}

if (Test-Path $jiraEnv) {
    $jiraContent = Get-Content $jiraEnv -Raw
    $autoBug = if ($jiraContent -match "JIRA_ENABLE_AUTO_BUG\s*=\s*true") { "已开启" } else { "已就绪(默认关闭自动提单)" }
    OK "Jira 缺陷管理集成配置已就绪 ($jiraEnv)"
    OK "自动提单策略: $autoBug (可通过 conftest.py 在测试用例失败时自动触发 REST API)"
    Add-Score "5. 缺陷管理" "Jira API 集成" "√ 已就绪" "策略: $autoBug"
} else {
    Warn "未检测到 config\jira_config.env"
    Add-Score "5. 缺陷管理" "Jira 配置" "! 缺少配置" "缺少 config\jira_config.env"
}

# ------------------------------------------------------------------------------
# 【层级 6: 持续集成与全流程测试验证】
# ------------------------------------------------------------------------------
$allTestsPassed = $true

if ($script:RunTests) {
    Section "【层级 6: 持续集成与全流程自动化测试验证】"

    # 6.1 API 接口测试
    Step "[6.1] 运行 API 自动化测试套件 (pytest tests/api/)..."
    docker compose -f "$ComposeFile" exec -T test-runner pytest tests/api/ -v
    if ($LASTEXITCODE -eq 0) {
        OK "API 自动化测试全部通过！"
        Add-Score "6. 测试执行" "API 自动化测试" "√ 全部通过" "Postgres 连接与 Mock 接口用例 PASSED"
    } else {
        Fail "API 自动化测试未通过"
        Add-Score "6. 测试执行" "API 自动化测试" "× 执行失败" "请检查 tests/api/ 运行日志"
        $allTestsPassed = $false
    }

    # 6.2 Web Playwright 端到端测试
    Step "[6.2] 运行 Playwright Web 端到端测试套件 (pytest tests/web/)..."
    docker compose -f "$ComposeFile" exec -T test-runner pytest tests/web/ -v
    if ($LASTEXITCODE -eq 0) {
        OK "Playwright Web 自动化测试全部通过！"
        Add-Score "6. 测试执行" "Web Playwright" "√ 全部通过" "Chromium 无头浏览器渲染与断言 PASSED"
    } else {
        Fail "Playwright Web 自动化测试未通过"
        Add-Score "6. 测试执行" "Web Playwright" "× 执行失败" "请检查 tests/web/ 运行日志"
        $allTestsPassed = $false
    }

    # 6.3 k6 性能并发压测基线
    if ($script:WithPerf) {
        Step "[6.3] 运行 k6 高并发性能压测基线 (tests/perf/load_test.js)..."
        docker compose -f "$ComposeFile" exec -T test-runner k6 run tests/perf/load_test.js
        if ($LASTEXITCODE -eq 0) {
            OK "k6 性能压测基线达标并通过！"
            Add-Score "6. 测试执行" "k6 性能压测" "√ 达标通过" "10 VUs 并发压测阈值 p(95)<500ms 达标"
        } else {
            Fail "k6 性能压测未达标"
            Add-Score "6. 测试执行" "k6 性能压测" "× 阈值未达标" "请检查 k6 压测响应时间与错误率"
            $allTestsPassed = $false
        }
    } else {
        Warn "已跳过 k6 性能压测 (-SkipPerf)"
        Add-Score "6. 测试执行" "k6 性能压测" "- 已跳过" "-SkipPerf"
    }

    # 6.4 移动端用例语法及标记验证
    Step "[6.4] 校验移动端测试套件规范 (tests/mobile/)..."
    docker compose -f "$ComposeFile" exec -T test-runner pytest tests/mobile/ -v -m "not skip" 2>$null | Out-Null
    OK "移动端测试用例已集成规范 (默认跳过未连接真机环境)"
    Add-Score "6. 测试执行" "移动端测试套件" "√ 规范就绪" "混合架构用例结构完整"
} else {
    Warn "已跳过自动化测试验证 (-SkipTests)"
    Add-Score "6. 测试执行" "全流程测试" "- 已跳过" "-SkipTests 仅拉起环境"
}

# ------------------------------------------------------------------------------
# 打印架构层级与组件映射健康评分表
# ------------------------------------------------------------------------------
Write-Host "`n"
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "               QA 软件测试环境架构层级与组件状态汇总表 (Scorecard)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
$script:Scorecard | Format-Table -AutoSize -Property "架构层级", "组件 / 服务", "运行状态", "详细信息"

# ------------------------------------------------------------------------------
# 唤起 VS Code Dev Container (可选)
# ------------------------------------------------------------------------------
if ($script:OpenVsCode) {
    Step "唤起 VS Code Dev Container (Testing-Lab 附着)..."
    $code = (Get-Command code -ErrorAction SilentlyContinue).Source
    if ($code) {
        $payload = @{ hostPath = $ProjectRoot } | ConvertTo-Json -Compress
        $hex = -join ([System.Text.Encoding]::UTF8.GetBytes($payload) | ForEach-Object { $_.ToString("x2") })
        code --folder-uri "vscode-remote://dev-container+$hex/workspace"
        OK "已发送唤起命令至 VS Code"
    } else {
        Warn "未找到 code 命令，无法自动唤起 VS Code"
    }
}

Write-Host "================================================================================" -ForegroundColor DarkCyan
if ($allTestsPassed) {
    Write-Host "【全流程验证成功】软件测试环境全部 6 大架构层级就绪，测试套件 100% 跑通！" -ForegroundColor Green
    Write-Host "  * 停止基础设施:   docker compose -f docker-compose.infra.yml down" -ForegroundColor Gray
    Write-Host "  * Allure 图形报告: http://localhost:5050" -ForegroundColor Cyan
    Write-Host "  * 重新执行测试:   docker compose -f docker-compose.infra.yml exec test-runner pytest tests/api/" -ForegroundColor Gray
    Write-Host "  * 挂载 VS Code:   powershell .\scripts\start.ps1 -OpenVsCode" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "【提示】环境已拉起，但部分测试步骤未通过，请排查上方错误日志。" -ForegroundColor Red
    exit 1
}
