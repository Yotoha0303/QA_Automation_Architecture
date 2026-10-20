# ------------------------------------------------------------------------------
# 强制终端控制台使用 UTF-8 编码，彻底杜绝中文乱码
# ------------------------------------------------------------------------------
chcp 65001 >$null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "QA Automation - Windows 宿主工具自动化部署"

# 0. 网络档位解析（-Mirror cn|global|auto|cache，透传给提权子进程）
$script:MirrorMode = "cache"
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Mirror" -and $i + 1 -lt $args.Count) { $script:MirrorMode = $args[$i + 1].ToLower() }
}
. (Join-Path $PSScriptRoot "network.ps1")
$script:QaNet = Resolve-QaNetwork -Mode $script:MirrorMode -TempDir "C:\QA_Installers_Temp"
Write-Host ("    网络档位: {0} (profile={1})" -f $(if ($script:QaNet.Profile -eq "cn") { "国内镜像" } else { "官方源" }), $script:QaNet.Profile) -ForegroundColor Cyan

# 1. 自动请求管理员权限
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "[*] 正在请求管理员权限启动..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mirror $script:MirrorMode"
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

$ProgressPreference = 'SilentlyContinue'

$DownloadDir = "C:\QA_Installers_Temp"
if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Windows 宿主环境与桌面工具自动安装 (自适应模式)        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 检查是否存在 winget
$HasWinget = (Get-Command winget -ErrorAction SilentlyContinue) -ne $null

if ($HasWinget) {
    Write-Host "[√] 检测到系统内置 winget，使用官方包管理器安装..." -ForegroundColor Green
    # 严格对齐文档矩阵：宿主只装桌面工具，运行时不装进系统
    $apps = @(
        @{ Name = "Visual Studio Code"; Id = "Microsoft.VisualStudioCode" },
        @{ Name = "Wireshark";          Id = "WiresharkFoundation.Wireshark" },
        @{ Name = "Apifox Desktop";     Id = "Ruihu.Apifox" },
        @{ Name = "Docker Desktop";     Id = "Docker.DockerDesktop" },
        @{ Name = "Git for Windows";    Id = "Git.Git" }
    )
    foreach ($app in $apps) {
        Write-Host "`n--> 正在安装: $($app.Name) ..." -ForegroundColor Yellow
        winget install --id $($app.Id) --silent --accept-package-agreements --accept-source-agreements --no-upgrade
    }
} else {
    Write-Host "[!] 未检测到 winget (全新/精简 Windows 系统)，自动切换为【官方直链静默下载安装】模式..." -ForegroundColor Yellow

    # 定义经端到端 HTTP 探测验证 100% 有效的官方真实直链
    $vs = Get-QaVSCodeSource
    $InstallTasks = @(
        @{
            Name     = "Visual Studio Code (64位)"
            FileName = if ($vs.FileName) { $vs.FileName } else { "VSCodeSetup-x64.exe" }
            Url      = $vs.Url
            Args     = "/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath"
        },
        @{
            Name     = "Wireshark (官方最新稳定版)"
            FileName = "Wireshark-latest-x64.exe"
            Url      = $script:QaFallbacks.Wireshark
            Args     = "/S"
        },
        @{
            Name     = "Apifox Desktop (官方真实直链)"
            FileName = "Apifox-setup.exe"
            Url      = $script:QaFallbacks.Apifox
            Args     = "/S"
        },
        @{
            Name     = "Docker Desktop (容器运行底座)"
            FileName = "DockerDesktopInstaller.exe"
            Url      = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
            Args     = "install --quiet --accept-license --backend=wsl-2"
        }
    )

    foreach ($task in $InstallTasks) {
        $filePath = Join-Path $DownloadDir $task.FileName
        Write-Host "`n----------------------------------------------------------" -ForegroundColor Gray
        Write-Host "--> 正在下载: $($task.Name) ..." -ForegroundColor Yellow
        Write-Host "    下载来源: $($task.Url)" -ForegroundColor DarkGray
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            Save-QaFile $task.Url $filePath 300 | Out-Null
            Write-Host "[√] 下载完成，正在静默安装: $($task.Name) ..." -ForegroundColor Green
            Start-Process -FilePath $filePath -ArgumentList $task.Args -Wait
            Write-Host "[√] $($task.Name) 安装完成！" -ForegroundColor Green
        } catch {
            Write-Host "[×] 安装 $($task.Name) 失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "【完成】所有 Windows 宿主工具已处理就绪！" -ForegroundColor Green
Write-Host "使用指引: " -ForegroundColor Cyan
Write-Host "1. 打开 VS Code，搜索并安装插件: Dev Containers"
Write-Host "2. 启动 Docker Desktop"
Write-Host "3. 项目根目录执行: docker compose -f docker-compose.infra.yml up -d"
Write-Host "==========================================================" -ForegroundColor Green
