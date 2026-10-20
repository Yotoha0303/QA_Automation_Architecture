# ------------------------------------------------------------------------------
# 网络环境与镜像源解析 (network.ps1)
#   本文件由其它脚本 dot-source 引入，统一管理：
#     - 国内镜像 / 国外代理的选择 (-Mirror cn|global|auto)
#     - GitHub Release 最新版本解析 (curl.exe 跟随重定向，不消耗 API 配额)
#     - 镜像感知的下载 (直连失败自动改用 GitHub 代理)
#   实测 (2026-10-20)：ghfast.top / gh-proxy.com 可用；vscode.cdn.azure.cn 已失效；
#                       npmmirror、清华 pypi、npmmirror playwright 镜像可用。
# ------------------------------------------------------------------------------

# 镜像配置：Global 全部置空 = 使用各官方源
$script:QaMirrors = @{
    Cn = @{
        GitHubProxy   = "https://ghfast.top"
        GitHubProxies = @("https://ghfast.top", "https://gh-proxy.com")
        PipIndex      = "https://pypi.tuna.tsinghua.edu.cn/simple"
        NpmRegistry   = "https://registry.npmmirror.com"
        PlaywrightCdn = "https://registry.npmmirror.com/-/binary/playwright"
        NodeMirror    = "https://npmmirror.com/mirrors/node"
    }
    Global = @{
        GitHubProxy   = ""
        GitHubProxies = @()
        PipIndex      = ""
        NpmRegistry   = ""
        PlaywrightCdn = ""
        NodeMirror    = ""
    }
}

# 镜像不可用时的兜底版本（2026-10-20 实测有效）
$script:QaFallbacks = @{
    GitTag        = "v2.56.0.windows.2"
    GitAsset      = "Git-2.56.0.2-64-bit.exe"
    Wireshark     = "https://www.wireshark.org/download/win64/Wireshark-latest-x64.exe"
    VSCode        = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"
    Apifox        = "https://file-assets.apifox.com/download/2.8.49/Apifox-2.8.49.exe"
}

function Test-QaUrl($url, $timeoutSec = 8) {
    try {
        $code = & curl.exe -s -o NUL -m $timeoutSec -w "%{http_code}" -I $url 2>$null
        return ($code -match '^(2|3)\d\d$')
    } catch { return $false }
}

# 自动探测：国内镜像与 GitHub 代理同时可达 => cn，否则 global
function Get-AutoNetworkProfile {
    $cnOk = (Test-QaUrl "https://registry.npmmirror.com" 5) -and (Test-QaUrl "https://pypi.tuna.tsinghua.edu.cn/simple/" 5)
    $ghProxyOk = Test-QaUrl "https://ghfast.top" 5
    if ($cnOk -or $ghProxyOk) {
        if ($cnOk -and $ghProxyOk) { return "cn" }
        # 只有一项可用时，仍选 cn 并逐项探测，缓存后会保留最终结论
        return "cn"
    }
    return "global"
}

# 解析生效的网络档位，结果缓存到 C:\QA_Installers_Temp\network_profile.txt
#   -Mode auto|cache|cn|global
#   auto  : 每次重新探测
#   cache : 复用上次探测结果（默认），没有缓存则探测
function Resolve-QaNetwork {
    param(
        [string]$Mode = "cache",
        [string]$TempDir = "C:\QA_Installers_Temp"
    )
    if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }
    $cacheFile = Join-Path $TempDir "network_profile.txt"

    $profile = $Mode
    if ($Mode -eq "cache") {
        if (Test-Path $cacheFile) {
            $saved = (Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($saved -in @("cn", "global")) { $profile = $saved } else { $profile = "auto" }
        } else {
            $profile = "auto"
        }
    }
    if ($profile -eq "auto") {
        $profile = Get-AutoNetworkProfile
        $profile | Out-File -FilePath $cacheFile -Encoding ascii
    }
    if ($profile -notin @("cn", "global")) { $profile = "global" }

    $net = $script:QaMirrors[$(if ($profile -eq "cn") { "Cn" } else { "Global" })] | ForEach-Object { $_ }
    $result = @{}
    foreach ($k in $net.Keys) { $result[$k] = $net[$k] }
    $result.Profile = $profile
    $result.CacheFile = $cacheFile

    # 选一个实际可用的 GitHub 代理（cn 档才需要）
    $result.GitHubProxy = ""
    if ($profile -eq "cn") {
        foreach ($p in $result.GitHubProxies) {
            if (Test-QaUrl $p 5) { $result.GitHubProxy = $p; break }
        }
        if (-not $result.GitHubProxy) { $result.GitHubProxy = "" }
    }
    return $result
}

# 为 URL 生成候选列表：先直连，再（国内档且是 GitHub 资源时）走代理
function Get-QaCandidateUrls($url) {
    $list = @($url)
    if ($script:QaNet -and $script:QaNet.GitHubProxy -and $url -match '^https://(github\.com|objects\.githubusercontent\.com)/') {
        $list += "$($script:QaNet.GitHubProxy)/$url"
    }
    return $list
}

# 镜像感知下载：逐个候选尝试，成功即返回；全部失败抛异常
function Save-QaFile($url, $outFile, $timeoutSec = 900) {
    $lastError = $null
    foreach ($candidate in (Get-QaCandidateUrls $url)) {
        try {
            if ($candidate -ne $url) { Write-Host "        直连失败，改用代理: $candidate" -ForegroundColor DarkGray }
            Invoke-WebRequest -Uri $candidate -OutFile $outFile -UseBasicParsing -TimeoutSec $timeoutSec
            if ((Test-Path $outFile) -and (Get-Item $outFile).Length -gt 0) { return $candidate }
        } catch {
            $lastError = $_.Exception.Message
            if (Test-Path $outFile) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue }
        }
    }
    throw "下载失败: $url ($lastError)"
}

# 跟随 /releases/latest 的重定向拿 tag（不调用 API，避免 403/限流）
function Get-QaGitHubLatestTag($repo) {
    try {
        # 用 url_effective 拿最终地址（redirect_url 在 -L 跟随完之后为空）
        $final = & curl.exe -sL -m 20 -o NUL -w "%{url_effective}" "https://github.com/$repo/releases/latest" 2>$null
        if ($final -match '/releases/tag/([^/\s]+)') { return $Matches[1] }
    } catch { }
    return $null
}

# 从 expanded_assets 页面解析实际资产文件名（不调用 API）
function Get-QaGitHubAsset($repo, $tag, $pattern) {
    $candidates = @("https://github.com/$repo/releases/expanded_assets/$tag")
    if ($script:QaNet -and $script:QaNet.GitHubProxy) {
        $candidates += "$($script:QaNet.GitHubProxy)/$($candidates[0])"
    }
    foreach ($u in $candidates) {
        try {
            $html = (& curl.exe -sL -m 20 $u 2>$null) -join "`n"
            $m = [regex]::Match($html, $pattern)
            if ($m.Success) { return $m.Value }
        } catch { }
    }
    return $null
}

function Get-QaGithubSource($repo, $assetPattern, $fallbackTag, $fallbackAsset, $label) {
    $tag = Get-QaGitHubLatestTag $repo
    if (-not $tag) { $tag = $fallbackTag; Write-Host "        [!] 无法解析 $label 最新版本，使用兜底版本 $tag" -ForegroundColor Yellow }
    $asset = Get-QaGitHubAsset $repo $tag $assetPattern
    if (-not $asset) { $asset = $fallbackAsset }
    return @{
        Url      = "https://github.com/$repo/releases/download/$tag/$asset"
        FileName = $asset
        Version  = $tag
    }
}

function Get-QaVSCodeSource {
    try {
        $json = (& curl.exe -s -m 20 "https://update.code.visualstudio.com/api/update/win32-x64-user/stable/latest" 2>$null) -join ""
        if ($json -match '"url"\s*:\s*"([^"]+)"') {
            $url = $Matches[1]
            return @{
                Url      = $url
                FileName = Split-Path $url -Leaf
                Version  = $(if ($json -match '"productVersion"\s*:\s*"([^"]+)"') { $Matches[1] } else { "" })
            }
        }
    } catch { }
    return @{
        Url      = $script:QaFallbacks.VSCode
        FileName = "VSCodeUserSetup-x64-latest.exe"
        Version  = ""
    }
}
