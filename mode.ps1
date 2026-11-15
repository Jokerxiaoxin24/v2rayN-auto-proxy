# mode.ps1 —— 切换"代理模式 / 直连模式（游戏模式）"
# 需要管理员权限：由气泡右键菜单通过计划任务 mode-direct、mode-proxy 调用
#
# 直连模式：名单里的程序必须先全部关掉 → 防火墙封锁它们 → 关掉 v2rayN → 清系统代理 → 放开出站
# 代理模式：直接交给 auto-proxy.ps1（开断网保护、拆封锁、启动 v2rayN、测网、弹通知）

param([ValidateSet('Direct', 'Proxy')][string]$Mode)

. "$PSScriptRoot\common.ps1"

if (-not (Test-Admin)) {
    Write-Host '需要管理员权限：请右键 PowerShell →「以管理员身份运行」，再执行一次。' -ForegroundColor Yellow
    exit 1
}

# 读名单，展开成电脑上真实存在的 exe 路径
function Get-SensitivePaths {
    $lines = Get-Content (Join-Path $PSScriptRoot 'sensitive-apps.txt') -Encoding UTF8 -ErrorAction SilentlyContinue |
             ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
    foreach ($line in $lines) {
        if ($line.StartsWith('appx:')) {
            # 商店程序：用包名找到安装位置，再拼上相对路径
            $pkgName, $rel = $line.Substring(5).Split('\', 2)
            foreach ($pkg in Get-AppxPackage -Name $pkgName -ErrorAction SilentlyContinue) {
                $p = Join-Path $pkg.InstallLocation $rel
                if (Test-Path $p) { $p }
            }
        } else {
            Resolve-Path ([Environment]::ExpandEnvironmentVariables($line)) -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }
        }
    }
}

# 通知正在运行的程序"代理设置变了"（跟 v2rayN 改代理时做的一样）
function Update-ProxySettings {
    Add-Type -Namespace Win -Name Inet -MemberDefinition '[DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);' -ErrorAction SilentlyContinue
    [Win.Inet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null   # SETTINGS_CHANGED
    [Win.Inet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null   # REFRESH
}

if ($Mode -eq 'Direct') {
    $paths = @(Get-SensitivePaths | Select-Object -Unique)
    $names = @($paths | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } | Select-Object -Unique)

    # 0. 再确认一遍：名单里的程序必须全关（气泡那边已经查过，这里是第二道保险）
    $still = @()
    if ($names.Count -gt 0) { $still = @(Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object ProcessName | Select-Object -Unique) }
    if ($still.Count -gt 0) {
        Write-Log "拒绝切直连：还开着 $($still -join '、')"
        Show-Toast '没有切到直连' "这些程序还开着：$($still -join '、')。先把它们关掉再切"
        exit 1
    }

    # 1. 封锁名单里的程序（Block 规则比任何放行规则都优先）
    Remove-NetFirewallRule -Group $BlockGroup -ErrorAction SilentlyContinue
    foreach ($p in $paths) {
        New-NetFirewallRule -DisplayName "直连封锁 - $(Split-Path $p -Leaf)" -Group $BlockGroup `
            -Direction Outbound -Action Block -Program $p | Out-Null
    }

    # 2. 关掉 v2rayN 和它的核心（它们是管理员权限启动的，所以这一步必须在这里做）
    Get-Process -Name v2rayN, xray, sing-box, mihomo -ErrorAction SilentlyContinue | Stop-Process -Force

    # 3. 清掉系统代理，不然别的程序还会去连已经没人在听的代理端口
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0
    Update-ProxySettings

    # 4. 放开出站（断网保护暂停），游戏才能直连
    Set-NetFirewallProfile -Profile Domain, Private, Public -DefaultOutboundAction Allow

    Set-Content -Path $ModeFile -Value 'direct' -Encoding ASCII
    Write-Log "直连模式：开启（封锁 $($paths.Count) 个程序：$((($paths | ForEach-Object { Split-Path $_ -Leaf }) | Select-Object -Unique) -join '、')）"
    Show-Toast '已切到直连模式 🎮' "名单里的 $($paths.Count) 个程序已被防火墙封锁。打完游戏右键气泡切回代理（重启电脑也会自动切回）"
}
else {
    Write-Log '切回代理模式'
    & "$PSScriptRoot\auto-proxy.ps1"
}
