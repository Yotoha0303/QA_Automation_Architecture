chcp 65001 > $null 2>&1
$log = "C:\QA_Installers_Temp\elevate_launch.log"
"=== 启动时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $log -Encoding utf8
$target = Join-Path $PSScriptRoot "1_safe_install.ps1"
try {
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $target + '"') -PassThru
    "已启动提权进程 PID: $($p.Id)" | Tee-Object -FilePath $log -Append
    $p.WaitForExit()
    "进程退出码: $($p.ExitCode)" | Tee-Object -FilePath $log -Append
} catch {
    "启动失败: $($_.Exception.Message)" | Tee-Object -FilePath $log -Append
    exit 1
}
"=== 结束时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $log -Append -Encoding utf8
