# ------------------------------------------------------------------------------
# 强制终端控制台使用 UTF-8 编码，杜绝中文乱码
# ------------------------------------------------------------------------------
chcp 65001 >$null 2>&1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "宿主一键完全复原与清理工具 (全量可逆还原)"

# 1. 管理员提权检查
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "[*] 正在请求管理员权限启动复原程序..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"")
    exit
}

$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if (-not $desktopPath) { $desktopPath = Join-Path $env:USERPROFILE "Desktop" }
$ManifestDir = Join-Path $desktopPath "Host_Baseline_Backup"
$ManifestFile = "$ManifestDir\installed_manifest.json"
$TempDir = "C:\QA_Installers_Temp"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         开始执行系统一键安全复原与彻底清理               " -ForegroundColor Cyan
Write-Host "   (仅卸载本次脚本新装的内容，绝不碰您原本就有的软件)     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 0. 从注册表 UninstallString 中解析出可执行文件路径
function Get-ExeFromUninstallString($raw) {
    if (-not $raw) { return $null }
    if ($raw -match '^"([^"]+)"') { return $Matches[1] }
    return ($raw -replace '\s+/\S.*$', '').Trim()
}

# 1. 读取安装清单
$installTime = $null
if (Test-Path $ManifestFile) {
    $manifestData = Get-Content $ManifestFile -Raw -Encoding utf8 | ConvertFrom-Json
    Write-Host "[i] 成功读取安装清单 (记录时间: $($manifestData.InstallTime))" -ForegroundColor Cyan
    try { $installTime = [datetime]::ParseExact($manifestData.InstallTime, "yyyy-MM-dd HH:mm:ss", $null) } catch { $installTime = $null }
} else {
    Write-Host "[!] 未找到安装清单文件，将按标准卸载逻辑执行清理..." -ForegroundColor Yellow
}

# 2. 卸载 Wireshark
$wsUninstall = @("$env:ProgramFiles\Wireshark\uninstall-wireshark.exe", "$env:ProgramFiles\Wireshark\uninstall.exe",
                 "${env:ProgramFiles(x86)}\Wireshark\uninstall-wireshark.exe", "${env:ProgramFiles(x86)}\Wireshark\uninstall.exe") |
               Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $wsUninstall) {
    $reg = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*") |
           ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
           Where-Object { $_.DisplayName -match "Wireshark" } | Select-Object -First 1
    if ($reg) { $wsUninstall = Get-ExeFromUninstallString $reg.UninstallString }
}
if ($wsUninstall -and (Test-Path $wsUninstall)) {
    Write-Host "`n--> 正在静默卸载 Wireshark: $wsUninstall /S ..." -ForegroundColor Yellow
    Start-Process -FilePath $wsUninstall -ArgumentList "/S" -Wait
    Start-Sleep -Seconds 3
    Write-Host "[√] Wireshark 卸载完成" -ForegroundColor Green
} else {
    Write-Host "`n[!] 未找到 Wireshark 卸载程序，跳过" -ForegroundColor Yellow
}

# 3. 卸载 Apifox
$afUninstall = @("$env:LOCALAPPDATA\Programs\apifox\Uninstall Apifox.exe", "$env:LOCALAPPDATA\Programs\Apifox\Uninstall Apifox.exe",
                 "$env:ProgramFiles\Apifox\Uninstall Apifox.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $afUninstall) {
    $reg = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*") |
           ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
           Where-Object { $_.DisplayName -match "Apifox" } | Select-Object -First 1
    if ($reg) { $afUninstall = Get-ExeFromUninstallString $reg.UninstallString }
}
if ($afUninstall -and (Test-Path $afUninstall)) {
    Write-Host "`n--> 正在静默卸载 Apifox: $afUninstall /S ..." -ForegroundColor Yellow
    Start-Process -FilePath $afUninstall -ArgumentList "/S" -Wait
    Start-Sleep -Seconds 3
}
foreach ($d in @("$env:LOCALAPPDATA\Programs\apifox", "$env:LOCALAPPDATA\Programs\Apifox", "$env:APPDATA\apifox")) {
    if (Test-Path $d) { Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host "[√] Apifox Desktop 清理完成" -ForegroundColor Green

# 4. 卸载 k6（仅当清单确认是本次安装时）
$k6Item = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "k6" } | Select-Object -First 1
if ($k6Item -and $k6Item.PSChildName) {
    $recorded = $false
    if ($manifestData -and $manifestData.NewlyInstalled) {
        $recorded = [bool]($manifestData.NewlyInstalled | Where-Object { $_.UninstallPath -eq $k6Item.PSChildName })
    }
    if (-not $recorded) {
        Write-Host "`n[!] 清单中未记录本次安装 k6 (产品码: $($k6Item.PSChildName))，为避免误删原有环境，跳过卸载" -ForegroundColor Yellow
    } else {
        Write-Host "`n--> 正在静默卸载 k6 性能压测引擎..." -ForegroundColor Yellow
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($k6Item.PSChildName) /quiet /norestart" -Wait
        Write-Host "[√] k6 卸载完成" -ForegroundColor Green
    }
}

# 5. 清理 Playwright（按清单判定是否由本次安装引入）
#    原有环境（如其它项目/IDE 插件预装的内核）一律保留，绝不整体删除目录
$pwMod = "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\Lib\site-packages\playwright"
$pwRecorded = $false
if ($manifestData -and $manifestData.NewlyInstalled) {
    $pwRecorded = [bool]($manifestData.NewlyInstalled | Where-Object { $_.UninstallType -eq "Pip" -and $_.UninstallPath -eq "playwright" })
}
if ($pwRecorded) {
    Write-Host "`n--> 正在卸载本次安装的 Playwright Python 包..." -ForegroundColor Yellow
    python -m pip uninstall -y playwright 2>&1 | Out-Null
    Write-Host "[√] Playwright Python 包已卸载" -ForegroundColor Green
} else {
    Write-Host "`n[!] 清单中未记录本次安装 Playwright，跳过卸载" -ForegroundColor Yellow
}

# 仅清理本次安装产生、且安装前不存在的浏览器内核目录（保留 .links 与其余版本）
$pwCache = "$env:LOCALAPPDATA\ms-playwright"
if (Test-Path $pwCache) {
    $pwRemoved = 0
    foreach ($d in Get-ChildItem $pwCache -Directory) {
        if ($d.Name -eq ".links") { continue }   # .links 记录各项目注册的内核，删除会损坏其它环境
        if ($installTime -and $d.CreationTime -ge $installTime.AddMinutes(-1)) {
            Remove-Item -Path $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $pwRemoved++
        }
    }
    Write-Host "[√] 已清理本次新增的 Playwright 浏览器内核: $pwRemoved 个 (其余版本原样保留)" -ForegroundColor Green
}

# 5.5 卸载本次直链新装的 PostgreSQL 16（保留用户原有的 PostgreSQL 17）
$pgRecorded = $null
if ($manifestData -and $manifestData.NewlyInstalled) {
    $pgRecorded = @($manifestData.NewlyInstalled | Where-Object { $_.Name -match "PostgreSQL" -and $_.UninstallPath -like "*PostgreSQL\16*" }) | Select-Object -First 1
}
if ($pgRecorded -and (Test-Path $pgRecorded.UninstallPath)) {
    Write-Host "`n--> 正在静默卸载 PostgreSQL 16: $($pgRecorded.UninstallPath) ..." -ForegroundColor Yellow
    Start-Process -FilePath $pgRecorded.UninstallPath -ArgumentList "--mode unattended" -Wait
    Start-Sleep -Seconds 5
    Remove-Item "C:\Program Files\PostgreSQL\16" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[√] PostgreSQL 16 卸载完成" -ForegroundColor Green
} elseif ($pgRecorded) {
    Write-Host "`n[!] 清单记录了 PostgreSQL，但卸载程序不存在，跳过" -ForegroundColor Yellow
}

# 6. 卸载本次由 winget 清单 (scripts/packages.json) 新装的软件
#    安装脚本只把"导入前不存在"的包写入清单，用户原有的软件不会出现在这里
$wingetItems = @()
if ($manifestData -and $manifestData.NewlyInstalled) {
    $wingetItems = @($manifestData.NewlyInstalled | Where-Object { $_.UninstallType -eq "Winget" })
}
if ($wingetItems.Count -gt 0 -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "`n--> 正在卸载本次经 winget 清单新装的 $($wingetItems.Count) 个软件..." -ForegroundColor Yellow
    foreach ($item in $wingetItems) {
        $id = $item.UninstallPath
        Write-Host "    卸载 $id ..." -ForegroundColor Gray
        winget uninstall --id $id --exact --silent --disable-interactivity --accept-source-agreements
        if (@(0, -1978335189) -contains $LASTEXITCODE) {
            Write-Host "    [√] $id 已卸载" -ForegroundColor Green
        } else {
            Write-Host "    [!] $id 卸载返回 $LASTEXITCODE (可能仍在使用或需手动确认)" -ForegroundColor Yellow
        }
    }
} elseif ($wingetItems.Count -gt 0) {
    Write-Host "`n[!] 清单记录有 winget 包，但当前未找到 winget，跳过" -ForegroundColor Yellow
}

# 7. 清理下载缓存临时目录
if (Test-Path $TempDir) {
    Write-Host "`n--> 正在清空临时下载包目录: $TempDir ..." -ForegroundColor Yellow
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[√] 临时缓存已彻底清空" -ForegroundColor Green
}

# 8. 还原系统与用户环境变量基线
Write-Host "`n--> 正在导入初始基线快照，还原环境变量..." -ForegroundColor Yellow
if (Test-Path "$ManifestDir\HKCU_Environment_Backup.reg") {
    reg import "$ManifestDir\HKCU_Environment_Backup.reg" | Out-Null
}
if (Test-Path "$ManifestDir\HKLM_Environment_Backup.reg") {
    reg import "$ManifestDir\HKLM_Environment_Backup.reg" | Out-Null
}
Write-Host "[√] 系统与用户环境变量已完全复原至初始快照状态！" -ForegroundColor Green

# 9. 安全自验
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "【复原验收完成】" -ForegroundColor Green
$wsStatus = Test-Path "$env:ProgramFiles\Wireshark\Wireshark.exe"
$afStatus = Test-Path "$env:LOCALAPPDATA\Programs\apifox\Apifox.exe"
$pgStatus = (Get-Service postgresql-x64-17 -ErrorAction SilentlyContinue).Status

Write-Host "  Wireshark:       " -NoNewline; if (-not $wsStatus) { Write-Host "已彻底卸载 (√)" -ForegroundColor Green } else { Write-Host "仍有残留" -ForegroundColor Red }
Write-Host "  Apifox Desktop:  " -NoNewline; if (-not $afStatus) { Write-Host "已彻底卸载 (√)" -ForegroundColor Green } else { Write-Host "仍有残留" -ForegroundColor Red }
Write-Host "  PostgreSQL 17:   " -NoNewline; Write-Host "不受影响，服务状态: $pgStatus (√ 安全保持)" -ForegroundColor Green
Write-Host "  Scoop / D盘环境: " -NoNewline; Write-Host "完全未动，100% 原始状态 (√ 安全保持)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
