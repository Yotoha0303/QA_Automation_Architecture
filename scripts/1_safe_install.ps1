# ------------------------------------------------------------------------------
# 软件测试环境全套标准安装程序 (显性安装 + 安装后自动校验)
#   默认行为：对所有组件执行显性安装（已存在则走官方静默升级/覆盖安装）
#   -VerifyOnly  ：只做校验，不安装
# ------------------------------------------------------------------------------
chcp 65001 >$null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------------------------
# 参数解析
#   -VerifyOnly          只检查，不安装
#   -InstallMissingOnly  已存在则跳过（旧版“保护式”行为）
#   -Only A,B,C          只处理指定组件（wireshark/apifox/vscode/git/playwright/winget）
#                        -Only 只走直链安装器，不执行 packages.json 全量清单
#   -InstallHostRuntime  运行时镜像不存在时，允许回退为宿主机 pip 安装 Playwright
#   -Mirror cn|global|auto|cache
#                        网络档位：国内镜像 / 官方源 / 重新探测 / 复用上次探测（默认 cache）
# ------------------------------------------------------------------------------
$script:VerifyOnly = $false
$script:InstallMissingOnly = $false
$script:OnlyFilter = @()
$script:MirrorMode = "cache"
$script:InstallHostRuntime = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^-VerifyOnly$'          { $script:VerifyOnly = $true }
        '^-InstallMissingOnly$'  { $script:InstallMissingOnly = $true }
        '^-Only$'                {
            if ($i + 1 -lt $args.Count) { $script:OnlyFilter = @($args[$i + 1].Split(',') | ForEach-Object { $_.Trim().ToLower() }); $i++ }
        }
        '^-InstallHostRuntime$'  { $script:InstallHostRuntime = $true }
        '^-Mirror$'              {
            if ($i + 1 -lt $args.Count) { $script:MirrorMode = $args[$i + 1].ToLower(); $i++ }
        }
        default { }
    }
}

# 1. 管理员权限检查（只校验不安装时不需要提权）
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin -and -not $script:VerifyOnly) {
    Write-Host "[*] 正在请求管理员权限启动..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($args.Count -gt 0) { $argList += " " + ($args -join " ") }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

$ManifestDir = "C:\Users\Yotoha\Desktop\Host_Baseline_Backup"
$ManifestFile = "$ManifestDir\installed_manifest.json"
$VerifyCsv    = "$ManifestDir\verify_result.csv"
$VerifyJson   = "$ManifestDir\verify_result.json"
$TempDir      = "C:\QA_Installers_Temp"
$LogFile      = "$TempDir\install_run.log"

if (-not (Test-Path $ManifestDir)) { New-Item -ItemType Directory -Path $ManifestDir -Force | Out-Null }
if (-not (Test-Path $TempDir))     { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

function Log-Msg($msg, $color = "Gray") {
    $ts = Get-Date -Format "HH:mm:ss"
    $formatted = "[$ts] $msg"
    Write-Host $formatted -ForegroundColor $color
    Add-Content -Path $LogFile -Value $formatted -Encoding utf8
}

$modeText = if ($script:VerifyOnly) { "仅校验 (不安装)" } elseif ($script:InstallMissingOnly) { "保护式安装 (已存在则跳过)" } else { "显性安装 (全量覆盖/升级)" }

Log-Msg "==========================================================" "Cyan"
Log-Msg "   软件测试环境全套标准安装程序" "Cyan"
Log-Msg "   当前模式: $modeText" "Cyan"
if ($script:OnlyFilter.Count -gt 0) { Log-Msg "   组件筛选: $($script:OnlyFilter -join ', ')" "Cyan" }
Log-Msg "==========================================================" "Cyan"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# ------------------------------------------------------------------------------
# 网络环境：国内镜像 / 国外代理 (见 scripts/network.ps1)
# ------------------------------------------------------------------------------
. (Join-Path $PSScriptRoot "network.ps1")
$script:QaNet = Resolve-QaNetwork -Mode $script:MirrorMode -TempDir $TempDir
$netLabel = if ($script:QaNet.Profile -eq "cn") { "国内镜像" } else { "官方源" }
Log-Msg "网络档位: $netLabel (profile=$($script:QaNet.Profile))" "Cyan"
if ($script:QaNet.Profile -eq "cn") {
    if ($script:QaNet.GitHubProxy) { Log-Msg "  GitHub 代理: $($script:QaNet.GitHubProxy)" "Cyan" }
    Log-Msg "  pip 镜像: $($script:QaNet.PipIndex)" "Cyan"
}

# 校验结果统一记录（脚本末尾输出 CSV / JSON）
$script:Results = @()

function Add-Result($name, $category, $ok, $detail) {
    $script:Results += [PSCustomObject]@{
        Time     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Name     = $name
        Category = $category
        Status   = if ($ok) { "已安装" } else { "未安装" }
        Passed   = [bool]$ok
        Detail   = $detail
    }
}

# 刷新当前进程的 PATH（从注册表重读机器/用户变量，安装后立即可见新命令）
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

# 获取官方安装包的真实大小（用于校验本地缓存是否完整）
function Get-RemoteFileSize($url) {
    foreach ($candidate in (Get-QaCandidateUrls $url)) {
        try {
            $r = Invoke-WebRequest -Uri $candidate -Method Head -UseBasicParsing -TimeoutSec 60
            $len = $r.Headers['Content-Length']
            if ($len) { return [int64]$len }
        } catch { }
    }
    return $null
}

# 下载并校验安装包：复用缓存前必须与官方大小一致，否则删除重下
function Get-ValidInstaller($name, $url, $fileName) {
    $filePath = Join-Path $TempDir $fileName
    $remoteSize = Get-RemoteFileSize $url

    if (Test-Path $filePath) {
        $localSize = (Get-Item $filePath).Length
        if (-not $remoteSize) {
            Log-Msg "    [警告] 无法获取官方包大小，为安全起见删除缓存并重新下载..." "Yellow"
            Remove-Item $filePath -Force -ErrorAction SilentlyContinue
        } elseif ($localSize -eq $remoteSize) {
            Log-Msg "    复用完整安装包（大小校验通过: $localSize 字节）" "Gray"
            return $filePath
        } else {
            Log-Msg "    [警告] 本地安装包不完整 (本地 $localSize / 官方 $remoteSize 字节)，删除并重新下载..." "Red"
            Remove-Item $filePath -Force -ErrorAction SilentlyContinue
        }
    }

    Log-Msg "    正在下载: $name ..." "Yellow"
    $partPath = "$filePath.part"
    if (Test-Path $partPath) { Remove-Item $partPath -Force -ErrorAction SilentlyContinue }
    # 国内档位下 GitHub 资源直连失败会自动改用代理
    Save-QaFile $url $partPath 900 | Out-Null
    Move-Item -Path $partPath -Destination $filePath -Force

    $finalSize = (Get-Item $filePath).Length
    if ($remoteSize -and $finalSize -ne $remoteSize) {
        throw "下载文件大小与官方不一致 (本地 $finalSize / 官方 $remoteSize 字节)"
    }
    Log-Msg "    下载完成并校验通过 (大小: $finalSize 字节)" "Gray"
    return $filePath
}

# 从注册表 UninstallString 中解析出可执行文件路径（兼容带参数与带引号的写法）
function Get-ExeFromUninstallString($raw) {
    if (-not $raw) { return $null }
    if ($raw -match '^"([^"]+)"') { return $Matches[1] }
    return ($raw -replace '\s+/\S.*$', '').Trim()
}

# 通用安装 + 校验流程
#   $detectBlock  已安装则返回非空描述，未安装返回 $null（同时用于安装后二次确认）
#   $versionBlock 返回简短版本号字符串（可为空）
function Install-StandardApp($name, $category, $url, $fileName, $silentArgs, $detectBlock, $versionBlock, $uninstallerFinder) {
    Log-Msg "--> [$category] $name" "Yellow"

    $existing = & $detectBlock

    # -VerifyOnly：只校验，不安装
    if ($script:VerifyOnly) {
        if ($existing) {
            $ver = & $versionBlock
            Log-Msg "    [√] 已安装  $existing $ver" "Green"
            Add-Result $name $category $true "$existing $ver"
        } else {
            Log-Msg "    [×] 未安装" "Red"
            Add-Result $name $category $false "未检测到安装产物"
        }
        return
    }

    if ($existing) {
        if ($script:InstallMissingOnly) {
            $ver = & $versionBlock
            Log-Msg "    [跳过] 已存在 ($existing $ver)，按 -InstallMissingOnly 保留" "Green"
            $Manifest.PreservedExisting += @{ Name = $name; Detail = "$existing $ver" }
            Add-Result $name $category $true "$existing $ver (已存在，跳过)"
            return
        }
        $ver = & $versionBlock
        Log-Msg "    [显性安装] 检测到已存在 ($existing $ver)，执行官方静默安装覆盖/升级..." "Cyan"
    }

    try {
        $filePath = Get-ValidInstaller $name $url $fileName
        Log-Msg "    正在执行官方静默安装..." "Gray"
        if ($fileName -match "\.msi$") {
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$filePath`" $silentArgs" -Wait -PassThru
        } else {
            $p = Start-Process -FilePath $filePath -ArgumentList $silentArgs -Wait -PassThru
        }
        Start-Sleep -Seconds 3

        # 0 = 成功；3010 / 1641 = 成功但需要重启
        if (@(0, 3010, 1641) -notcontains $p.ExitCode) {
            throw "安装程序返回非零退出码: $($p.ExitCode)"
        }

        # 以实际产物二次校验，杜绝“安装器报成功但其实没装上”的假成功
        Update-SessionPath
        $verified = & $detectBlock
        if (-not $verified) {
            throw "安装程序已退出，但未检测到安装产物，判定为安装失败"
        }

        $ver = & $versionBlock
        $uninstInfo = & $uninstallerFinder
        if (-not $uninstInfo.Path) {
            Log-Msg "    [警告] $name 已安装，但未定位到卸载程序，复原清单需人工补充" "Yellow"
        }
        Log-Msg "    [√] $name 安装完成并校验通过: $verified $ver" "Green"

        $Manifest.NewlyInstalled += @{
            Name          = $name
            InstallTime   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            UninstallType = $uninstInfo.Type
            UninstallPath = $uninstInfo.Path
            UninstallArgs = $uninstInfo.Args
        }
        Add-Result $name $category $true "$verified $ver"
    } catch {
        Log-Msg "    [×] $name 安装失败: $($_.Exception.Message)" "Red"
        Add-Result $name $category $false $_.Exception.Message
    }
}

# ------------------------------------------------------------------------------
# 读取已有清单并合并，避免重跑覆盖历史卸载记录
# ------------------------------------------------------------------------------
$Manifest = @{
    InstallTime       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    NewlyInstalled    = @()
    PreservedExisting = @()
}
if (Test-Path $ManifestFile) {
    try {
        $old = Get-Content $ManifestFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($old.NewlyInstalled)    { $Manifest.NewlyInstalled    = @($old.NewlyInstalled) }
        if ($old.PreservedExisting) { $Manifest.PreservedExisting = @($old.PreservedExisting) }
        $Manifest.OriginalInstallTime = $old.InstallTime
        Log-Msg "[i] 已加载历史清单 (原始安装时间: $($old.InstallTime))，本次结果将合并写入" "Cyan"
    } catch {
        Log-Msg "[!] 历史清单读取失败，将生成新清单: $($_.Exception.Message)" "Yellow"
    }
}

# ------------------------------------------------------------------------------
# 版本解析：GitHub 最新 Release（不调用 API，失败用兜底版本）
# ------------------------------------------------------------------------------
$script:Versions = @{}
function Get-InstallSource($key) {
    if (-not $script:Versions.ContainsKey($key)) {
        switch ($key) {
            "git" { $script:Versions[$key] = Get-QaGithubSource "git-for-windows/git" 'Git-[0-9.]+(\.[0-9]+)?-64-bit\.exe' $script:QaFallbacks.GitTag $script:QaFallbacks.GitAsset "Git" }
            "vscode" { $script:Versions[$key] = Get-QaVSCodeSource }
            default { $script:Versions[$key] = $null }
        }
    }
    return $script:Versions[$key]
}

function Should-Run($keywords) {
    if ($script:OnlyFilter.Count -eq 0) { return $true }
    foreach ($k in $keywords) {
        if ($script:OnlyFilter -contains $k.ToLower()) { return $true }
    }
    return $false
}

# ------------------------------------------------------------------------------
# 0. 宿主依赖清单 (scripts/packages.json -> winget import)
#    对齐《软件测试环境安装方式建议》: winget import -i packages.json
#    清单覆盖的桌面/命令行工具不再走直链重复安装；无 winget 时自动回退直链模式
# ------------------------------------------------------------------------------
$script:UseDirectLinks = $true

if (Should-Run @("winget", "packages", "manifest", "宿主")) {
    Log-Msg "--> [一键清单] 宿主依赖 (scripts/packages.json)" "Yellow"
    $PackagesFile = Join-Path $PSScriptRoot "packages.json"
    $WingetCmd = Get-Command winget -ErrorAction SilentlyContinue

    if (-not (Test-Path $PackagesFile)) {
        Log-Msg "    [!] 未找到 packages.json，后续组件改用直链安装" "Yellow"
    } elseif (-not $WingetCmd) {
        Log-Msg "    [!] 未检测到 winget，后续组件改用直链安装" "Yellow"
        if (-not $script:VerifyOnly) {
            Add-Result "宿主依赖清单 (packages.json)" "一键清单" $false "未检测到 winget，已回退直链安装模式"
        }
    } else {
        $pkgIds = @()
        try {
            $pkgIds = @((Get-Content $PackagesFile -Raw -Encoding utf8 | ConvertFrom-Json).Sources.Packages.PackageIdentifier)
        } catch {
            Log-Msg "    [×] packages.json 解析失败: $($_.Exception.Message)" "Red"
        }

        if ($script:VerifyOnly) {
            $missing = @()
            foreach ($id in $pkgIds) {
                $out = (winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String)
                if ($out -notmatch [regex]::Escape($id)) { $missing += $id }
            }
            if ($missing.Count -eq 0) {
                Log-Msg "    [√] 清单内 $($pkgIds.Count) 个包均已安装" "Green"
                Add-Result "宿主依赖清单 (packages.json)" "一键清单" $true "$($pkgIds.Count)/$($pkgIds.Count) 个包已安装"
            } else {
                Log-Msg "    [×] 缺失 $($missing.Count) 个包: $($missing -join ', ')" "Red"
                Add-Result "宿主依赖清单 (packages.json)" "一键清单" $false "缺失: $($missing -join ', ')"
            }
        } else {
            # 导入前先记录已存在的包：复原脚本只卸载本次真正新装的软件
            $preExisting = @()
            foreach ($id in $pkgIds) {
                $out = (winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String)
                if ($out -match [regex]::Escape($id)) { $preExisting += $id }
            }

            Log-Msg "    正在执行: winget import -i packages.json ..." "Gray"
            winget import -i $PackagesFile --accept-package-agreements --accept-source-agreements --disable-interactivity
            $importCode = $LASTEXITCODE

            # 以清单实际落地情况判定结果（winget import 在"全部已安装"时也会返回非 0）
            Update-SessionPath
            $missing = @()
            foreach ($id in $pkgIds) {
                $out = (winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String)
                if ($out -notmatch [regex]::Escape($id)) { $missing += $id }
            }

            if ($missing.Count -eq 0) {
                $script:UseDirectLinks = $false
                Log-Msg "    [√] 宿主依赖清单安装完成 (winget 退出码 $importCode)，清单内工具跳过直链安装" "Green"
                Add-Result "宿主依赖清单 (packages.json)" "一键清单" $true "$($pkgIds.Count) 个包已由 winget 处理"
                $newIds = @($pkgIds | Where-Object { $preExisting -notcontains $_ })
                foreach ($id in $newIds) {
                    if (-not ($Manifest.NewlyInstalled | Where-Object { $_.UninstallType -eq "Winget" -and $_.UninstallPath -eq $id })) {
                        $Manifest.NewlyInstalled += @{
                            Name          = "winget:$id"
                            InstallTime   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                            UninstallType = "Winget"
                            UninstallPath = $id
                            UninstallArgs = "--silent"
                        }
                    }
                }
                if ($preExisting.Count -gt 0) {
                    Log-Msg "    清单中 $($preExisting.Count) 个包在安装前已存在，复原时不会卸载: $($preExisting -join ', ')" "Gray"
                }
            } else {
                Log-Msg "    [!] winget import 退出码 $importCode，仍有 $($missing.Count) 个包未落地，这些组件将回退直链安装" "Yellow"
                Add-Result "宿主依赖清单 (packages.json)" "一键清单" $false "未落地: $($missing -join ', ')"
            }
        }
    }
}

# ------------------------------------------------------------------------------
# 1. Wireshark
# ------------------------------------------------------------------------------
if (Should-Run @("wireshark", "抓包")) {
    if (-not $script:UseDirectLinks) {
        Log-Msg "    [跳过] 已由 winget 清单 (packages.json) 负责，避免重复安装" "Gray"
    } else {
    Install-StandardApp "Wireshark (网络抓包)" "抓包与底层协议" `
        $script:QaFallbacks.Wireshark `
        "Wireshark-latest-x64.exe" `
        "/S" `
        {
            $p = @("$env:ProgramFiles\Wireshark\Wireshark.exe", "D:\Wireshark\Wireshark.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            return $p
        } `
        {
            $p = @("$env:ProgramFiles\Wireshark\Wireshark.exe", "D:\Wireshark\Wireshark.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($p) { return "v" + (Get-Item $p).VersionInfo.FileVersion }
            return ""
        } `
        {
            # 4.x 的卸载器是 uninstall-wireshark.exe；旧版本为 uninstall.exe，两者都兼容
            $u = @("$env:ProgramFiles\Wireshark\uninstall-wireshark.exe", "$env:ProgramFiles\Wireshark\uninstall.exe",
                   "${env:ProgramFiles(x86)}\Wireshark\uninstall-wireshark.exe", "${env:ProgramFiles(x86)}\Wireshark\uninstall.exe") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $u) {
                $reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -match "Wireshark" } | Select-Object -First 1
                if ($reg) { $u = Get-ExeFromUninstallString $reg.UninstallString }
            }
            return @{ Type = "Exe"; Path = $u; Args = "/S" }
        }
    }
}

# ------------------------------------------------------------------------------
# 2. Apifox Desktop
# ------------------------------------------------------------------------------
if (Should-Run @("apifox", "接口")) {
    if (-not $script:UseDirectLinks) {
        Log-Msg "    [跳过] 已由 winget 清单 (packages.json) 负责，避免重复安装" "Gray"
    } else {
    Install-StandardApp "Apifox Desktop (接口协同调试)" "API 协同与调试" `
        $script:QaFallbacks.Apifox `
        "Apifox-setup.exe" `
        "/S" `
        {
            $p = @("$env:LOCALAPPDATA\Programs\Apifox\Apifox.exe", "$env:LOCALAPPDATA\Programs\apifox\Apifox.exe",
                   "$env:ProgramFiles\Apifox\Apifox.exe", "D:\Apifox\Apifox.exe") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
            return $p
        } `
        {
            $p = @("$env:LOCALAPPDATA\Programs\Apifox\Apifox.exe", "$env:LOCALAPPDATA\Programs\apifox\Apifox.exe",
                   "$env:ProgramFiles\Apifox\Apifox.exe", "D:\Apifox\Apifox.exe") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($p) { return "v" + (Get-Item $p).VersionInfo.FileVersion }
            return ""
        } `
        {
            $u = @("$env:LOCALAPPDATA\Programs\Apifox\Uninstall Apifox.exe", "$env:LOCALAPPDATA\Programs\apifox\Uninstall Apifox.exe",
                   "$env:ProgramFiles\Apifox\Uninstall Apifox.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $u) {
                $reg = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*") |
                       ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
                       Where-Object { $_.DisplayName -match "Apifox" } | Select-Object -First 1
                if ($reg) { $u = Get-ExeFromUninstallString $reg.UninstallString }
            }
            return @{ Type = "Exe"; Path = $u; Args = "/S" }
        }
    }
}

# ------------------------------------------------------------------------------
# 3. Visual Studio Code
# ------------------------------------------------------------------------------
if (Should-Run @("vscode", "code", "编辑器")) {
    if (-not $script:UseDirectLinks) {
        Log-Msg "    [跳过] 已由 winget 清单 (packages.json) 负责，避免重复安装" "Gray"
    } else {
    Install-StandardApp "Visual Studio Code" "主开发与调试 IDE" `
        (Get-InstallSource "vscode").Url `
        (Get-InstallSource "vscode").FileName `
        "/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath" `
        {
            $c = Get-Command code -ErrorAction SilentlyContinue
            if ($c) { return $c.Source }
            return @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "D:\Microsoft VS Code\Code.exe") |
                   Where-Object { Test-Path $_ } | Select-Object -First 1
        } `
        {
            $c = Get-Command code -ErrorAction SilentlyContinue
            if ($c) { return "v" + (code -v 2>$null | Select-Object -First 1) }
            return ""
        } `
        {
            $u = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\unins000.exe", "D:\Microsoft VS Code\unins000.exe") |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
            return @{ Type = "Exe"; Path = $u; Args = "/VERYSILENT" }
        }
    }
}

# ------------------------------------------------------------------------------
# 4. Git for Windows
# ------------------------------------------------------------------------------
if (Should-Run @("git", "shell")) {
    if (-not $script:UseDirectLinks) {
        Log-Msg "    [跳过] 已由 winget 清单 (packages.json) 负责，避免重复安装" "Gray"
    } else {
    Install-StandardApp "Git for Windows (Shell/Bash)" "命令行终端支撑" `
        (Get-InstallSource "git").Url `
        (Get-InstallSource "git").FileName `
        "/SILENT /NORESTART" `
        {
            $g = Get-Command git -ErrorAction SilentlyContinue
            if ($g) { return $g.Source }
            return $null
        } `
        {
            $g = Get-Command git -ErrorAction SilentlyContinue
            if ($g) { return (git --version) }
            return ""
        } `
        {
            $u = @("$env:ProgramFiles\Git\unins000.exe", "D:\Git\unins000.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            return @{ Type = "Exe"; Path = $u; Args = "/VERYSILENT" }
        }
    }
}

# ------------------------------------------------------------------------------
# 5. Playwright & Python 运行时 (文档矩阵: 运行在 Dev Container)
#    默认只做校验，不向宿主机 Python 安装任何包；
#    仅当镜像不存在且指定 -InstallHostRuntime 时才回退到宿主机安装。
# ------------------------------------------------------------------------------
if (Should-Run @("playwright", "python", "自动化", "runtime")) {
    Log-Msg "--> [端到端自动化] Playwright & Python 运行时" "Yellow"

    $pwVerifyScript = @"
from playwright.sync_api import sync_playwright
import importlib.metadata as m
try:
    ver = m.version('playwright')
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        b.close()
    print(f'OK playwright=={ver}')
except Exception as e:
    print(f'ERR: {e}')
"@

    $hostReady = $false
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $r = python -c $pwVerifyScript 2>&1
        $hostReady = ($r -match "OK")
    }

    $imageReady = $false
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker image inspect qa-runtime:local *> $null
        $imageReady = ($LASTEXITCODE -eq 0)
    }

    if ($hostReady) {
        Log-Msg "    [√] 宿主机 Playwright 已可用（容器内同样可用）" "Green"
        Add-Result "Playwright & Python 运行时" "端到端自动化" $true "宿主机已就绪: $r"
    } elseif ($imageReady) {
        Log-Msg "    [√] 运行时由容器 qa-runtime:local 提供（宿主机未安装，符合文档矩阵）" "Green"
        Add-Result "Playwright & Python 运行时" "端到端自动化" $true "容器镜像 qa-runtime:local 已就绪"
    } elseif ($script:VerifyOnly) {
        Log-Msg "    [×] 宿主机与容器均未就绪" "Red"
        Add-Result "Playwright & Python 运行时" "端到端自动化" $false "宿主机未安装，且 qa-runtime:local 镜像不存在"
    } elseif ($script:InstallHostRuntime) {
        Log-Msg "    未找到 qa-runtime:local，按 -InstallHostRuntime 回退到宿主机安装..." "Yellow"
        $pipArgs = @("-m", "pip", "install", "--upgrade", "playwright", "pytest", "pytest-html", "Appium-Python-Client", "requests", "psycopg2-binary", "--quiet")
        if ($script:QaNet.PipIndex) { $pipArgs += @("-i", $script:QaNet.PipIndex) }
        python @pipArgs
        if ($LASTEXITCODE -ne 0) {
            Add-Result "Playwright & Python 运行时" "端到端自动化" $false "pip 退出码 $LASTEXITCODE"
        } else {
            if ($script:QaNet.PlaywrightCdn) { $env:PLAYWRIGHT_DOWNLOAD_HOST = $script:QaNet.PlaywrightCdn }
            python -m playwright install chromium
            $r = python -c $pwVerifyScript 2>&1
            if ($r -match "OK") {
                Log-Msg "    [√] 宿主机 Playwright 已就绪: $r" "Green"
                if (-not ($Manifest.NewlyInstalled | Where-Object { $_.UninstallType -eq "Pip" -and $_.UninstallPath -eq "playwright" })) {
                    $Manifest.NewlyInstalled += @{
                        Name          = "Playwright (宿主机)"
                        InstallTime   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        UninstallType = "Pip"
                        UninstallPath = "playwright"
                        UninstallArgs = ""
                    }
                }
                Add-Result "Playwright & Python 运行时" "端到端自动化" $true "$r"
            } else {
                Add-Result "Playwright & Python 运行时" "端到端自动化" $false "$r"
            }
        }
    } else {
        Log-Msg "    [×] 运行时镜像 qa-runtime:local 不存在" "Red"
        Log-Msg "    请执行 scripts\start.ps1 构建容器运行时（或加 -InstallHostRuntime 装到宿主机）" "Yellow"
        Add-Result "Playwright & Python 运行时" "端到端自动化" $false "需先构建 qa-runtime:local (scripts\start.ps1)"
    }
}

# ------------------------------------------------------------------------------
# 输出校验结果
# ------------------------------------------------------------------------------
if ($script:Results.Count -gt 0) {
    try { $script:Results | Export-Csv -Path $VerifyCsv -NoTypeInformation -Encoding UTF8 } catch { }
    try { $script:Results | ConvertTo-Json -Depth 4 | Out-File $VerifyJson -Encoding utf8 } catch { }
}

Log-Msg ""
Log-Msg "==================== 安装 / 校验结果 ====================" "Cyan"
foreach ($r in $script:Results) {
    $mark  = if ($r.Passed) { "√" } else { "×" }
    $color = if ($r.Passed) { "Green" } else { "Red" }
    Log-Msg ("  {0} {1,-42} {2,-14} {3}" -f $mark, $r.Name, $r.Status, $r.Detail) $color
}
$passCount = @($script:Results | Where-Object { $_.Passed }).Count
$totalCount = $script:Results.Count
Log-Msg ("  合计: {0}/{1} 项通过" -f $passCount, $totalCount) $(if ($passCount -eq $totalCount) { "Green" } else { "Yellow" })
Log-Msg "========================================================" "Cyan"

if (-not $script:VerifyOnly) {
    # 按组件名去重（重跑/重复安装时保留最新一条记录）
    $Manifest.NewlyInstalled = @($Manifest.NewlyInstalled | Group-Object Name | ForEach-Object { $_.Group | Select-Object -Last 1 })
    $Manifest.PreservedExisting = @($Manifest.PreservedExisting | Group-Object Name | ForEach-Object { $_.Group | Select-Object -Last 1 })
    $Manifest | ConvertTo-Json -Depth 6 | Out-File $ManifestFile -Encoding utf8
    Log-Msg "【清单已更新】$ManifestFile" "Green"
}
Log-Msg "【校验结果已输出】$VerifyCsv" "Green"
Log-Msg "【JSON 结果】$VerifyJson" "Green"
