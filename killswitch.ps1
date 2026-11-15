# killswitch.ps1 —— 断网保护（kill switch）
# 思路：防火墙"出站默认拦截"，只放行三种流量：
#   ① 从 TUN 网卡出去的（代理正常时，所有程序都走这里）
#   ② 去局域网的（路由器后台、局域网联机，不算"出国"）
#   ③ v2rayN 和它的核心程序（它们本来就要从 Wi-Fi 去连节点）
# 代理一断、TUN 一没，程序的流量只能从 Wi-Fi 直接出去 → 不在放行名单里 → 被拦下，中国 IP 漏不出去。
# （本机内部的 127.0.0.1 不受防火墙管，所以走系统代理的程序也不受影响）
#
# 用法（需要管理员权限）：
#   powershell -File killswitch.ps1 -Mode On       开启
#   powershell -File killswitch.ps1 -Mode Off      临时关闭（比如要登录校园网认证页）
#   powershell -File killswitch.ps1 -Mode Status   只看状态

param([ValidateSet('On', 'Off', 'Status')][string]$Mode = 'Status')

. "$PSScriptRoot\common.ps1"

# 改防火墙需要管理员权限：不是管理员就先说清楚，别刷一屏红字
if ($Mode -ne 'Status' -and -not (Test-Admin)) {
    Write-Host '需要管理员权限：请右键 PowerShell →「以管理员身份运行」，再执行一次。' -ForegroundColor Yellow
    exit 1
}

# 放行规则：不存在才建，所以重复运行不会越建越多
# 只在自己的规则组里找：别的组里有同名规则（比如旧版留下的）不算数，不然会以为"已经有了"而不建
function Ensure-Allow($name, [hashtable]$extra) {
    $mine = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Where-Object { $_.Group -eq $KsGroup }
    if (-not $mine) {
        New-NetFirewallRule -DisplayName $name -Group $KsGroup -Direction Outbound -Action Allow @extra | Out-Null
        Write-Log "新建放行规则：$name"
    }
}

switch ($Mode) {
    'On' {
        # 找不到 v2rayN 就不开：不然连 v2rayN 自己都会被拦住，整台电脑彻底断网
        if (-not $V2rayNExe -or -not (Test-Path $V2rayNExe)) {
            Write-Log "断网保护：没开（找不到 v2rayN：$V2rayNDir）"
            Show-Toast '断网保护没开 ⚠' '找不到 v2rayN：重新运行一次 install.ps1，或者改 config.ps1 里的 $V2rayNDir' -Alarm
            exit 1
        }
        Ensure-Allow '断网保护 - 放行 TUN'    @{ LocalAddress  = $TunNet }
        Ensure-Allow '断网保护 - 放行局域网'  @{ RemoteAddress = 'LocalSubnet' }
        # v2rayN 本体 + bin 文件夹里所有的核心（xray、sing-box、mihomo……v2rayN 更新后多出来的也会自动补上）
        $exes = @(Get-Item $V2rayNExe) + @(Get-ChildItem (Join-Path $V2rayNDir 'bin') -Recurse -Filter *.exe -ErrorAction SilentlyContinue)
        foreach ($exe in $exes) {
            Ensure-Allow "断网保护 - 放行 $($exe.Name)" @{ Program = $exe.FullName }
        }
        # 打开防火墙，出站默认改成"拦截"：上面没放行的，一律出不去
        Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -DefaultOutboundAction Block
        Write-Log '断网保护：开启'
    }
    'Off' {
        # 只把出站默认改回"放行"，防火墙本身继续开着
        Set-NetFirewallProfile -Profile Domain, Private, Public -DefaultOutboundAction Allow
        Write-Log '断网保护：临时关闭'
    }
}

# 不管哪种模式，最后都报告一下当前状态
Get-NetFirewallProfile | ForEach-Object { "{0,-8} 防火墙={1,-5} 出站默认={2}" -f $_.Name, $_.Enabled, $_.DefaultOutboundAction }
"放行规则：" + ((Get-NetFirewallRule -Group $KsGroup -ErrorAction SilentlyContinue | ForEach-Object DisplayName) -join ' | ')
