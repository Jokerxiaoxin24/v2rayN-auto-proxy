# mode.ps1 —— 切换"代理模式 / 直连模式（游戏模式）"
# 需要管理员权限：由气泡右键菜单通过计划任务 mode-direct、mode-proxy 调用
#
# 直连模式有两档（config.ps1 里的 $DirectProxyApps）：
#   $false（默认，最严格）：名单里的程序必须先全关 → 防火墙封锁它们 → 关掉 v2rayN → 清系统代理 → 放开出站
#   $true（名单程序走代理）：名单里的程序不用关 → 防火墙封锁它们直连外网 → v2rayN 关掉 TUN 后重新启动
#         （系统代理留着）→ 放开出站。游戏不再被 TUN 接走，直接走自己的网络；名单程序只能通过
#         本机的系统代理（127.0.0.1 不受防火墙管）出去，代理一断它们就断网，中国 IP 漏不出去
# 代理模式：直接交给 auto-proxy.ps1（开断网保护、拆封锁、恢复 TUN、启动 v2rayN、测网、弹通知）

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

    $list  = (($paths | ForEach-Object { Split-Path $_ -Leaf }) | Select-Object -Unique) -join '、'

    # 0. 最严格那档：名单里的程序必须全关（气泡那边已经查过，这里是第二道保险）
    if (-not $DirectProxyApps) {
        $still = @()
        if ($names.Count -gt 0) { $still = @(Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object ProcessName | Select-Object -Unique) }
        if ($still.Count -gt 0) {
            Write-Log "拒绝切直连：还开着 $($still -join '、')"
            Show-Toast '没有切到直连' "这些程序还开着：$($still -join '、')。先把它们关掉再切"
            exit 1
        }
    }

    # 1. 封锁名单里的程序直连外网（Block 规则比任何放行规则都优先；连本机 127.0.0.1 的代理不受防火墙管）
    Remove-NetFirewallRule -Group $BlockGroup -ErrorAction SilentlyContinue
    foreach ($p in $paths) {
        New-NetFirewallRule -DisplayName "直连封锁 - $(Split-Path $p -Leaf)" -Group $BlockGroup `
            -Direction Outbound -Action Block -Program $p | Out-Null
    }

    # 2. 关掉 v2rayN 和它的核心（它们是管理员权限启动的，所以这一步必须在这里做）
    Stop-V2rayN

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if ($DirectProxyApps) {
        # 3. 关掉 TUN 再启动 v2rayN：游戏流量不再被 TUN 接走；名单程序继续通过系统代理走代理
        #    （本来就没开 TUN 的话什么都不改，也不留标记，免得切回代理时把别人的 TUN 打开）
        if ($V2Tun) {
            Set-V2rayNTun $false
            Set-Content -Path $TunRestoreFile -Value 'v2rayN 的 TUN 被直连模式临时关掉了，回到代理模式时会自动打开' -Encoding UTF8
        }
        Start-Process -FilePath $V2rayNExe -WorkingDirectory $V2rayNDir
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Listening $V2Port) -and $sw.ElapsedMilliseconds -lt 30000) { Start-Sleep -Milliseconds 200 }
        $ready = Test-Listening $V2Port
        # 系统代理要开着，名单程序才会去连 v2rayN（v2rayN 设成"自动配置系统代理"时它自己会开，没开的话这里补上）
        if ((Get-ItemProperty $key).ProxyEnable -ne 1) {
            Set-ItemProperty $key -Name ProxyServer -Value "127.0.0.1:$V2Port"
            Set-ItemProperty $key -Name ProxyEnable -Value 1
            Update-ProxySettings
        }
    } else {
        # 3. 清掉系统代理，不然别的程序还会去连已经没人在听的代理端口
        Set-ItemProperty $key -Name ProxyEnable -Value 0
        Update-ProxySettings
    }

    # 4. 放开出站（断网保护暂停），游戏才能直连
    Set-NetFirewallProfile -Profile Domain, Private, Public -DefaultOutboundAction Allow

    if ($DirectProxyApps) {
        Set-Content -Path $ModeFile -Value 'direct-proxy' -Encoding ASCII
        Write-Log "直连模式（名单程序走代理）：开启（$($paths.Count) 个程序只能走代理：$list；代理端口就绪=$ready）"
        if ($ready) {
            Show-Toast '已切到直连模式 🎮' "游戏直连；浏览器这些名单程序照常走代理，代理断了它们就断网。打完游戏右键气泡切回代理（重启也会自动切回）"
        } else {
            Show-Toast '已切到直连模式，但代理没起来 ⚠' '游戏可以直连；名单里的程序暂时连不上网（不会漏 IP）。可以右键气泡切回代理模式再试'
        }
    } else {
        Set-Content -Path $ModeFile -Value 'direct' -Encoding ASCII
        Write-Log "直连模式：开启（封锁 $($paths.Count) 个程序：$list）"
        Show-Toast '已切到直连模式 🎮' "名单里的 $($paths.Count) 个程序已被防火墙封锁。打完游戏右键气泡切回代理（重启电脑也会自动切回）"
    }
}
else {
    Write-Log '切回代理模式'
    & "$PSScriptRoot\auto-proxy.ps1"
}
