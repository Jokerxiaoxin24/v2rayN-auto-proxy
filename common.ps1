# common.ps1 —— 几个脚本共用的设置和工具函数
# 别的脚本开头都会 . "$PSScriptRoot\common.ps1"，把这里的变量和函数"贴"进去

# ---- 版本：发新版时改这里（跟 GitHub Releases 上的版本号对应，比如 v1.1.0 就写 1.1.0）----
$AppVersion = '1.0.0'
$RepoSlug   = 'Jokerxiaoxin24/v2rayN-auto-proxy'     # 去哪个 GitHub 仓库查新版本

# ---- 名字：计划任务文件夹、防火墙规则组 ----
$AppName    = 'auto-proxy'
$TaskFolder = "\$AppName\"                 # 计划任务都放在任务计划程序的这个文件夹里
$KsGroup    = "$AppName 断网保护"          # 断网保护的放行规则
$BlockGroup = "$AppName 直连模式封锁"      # 直连模式下封锁名单程序的规则
$LogFile    = Join-Path $PSScriptRoot 'auto-proxy.log'
$ModeFile   = Join-Path $PSScriptRoot 'mode.txt'

# ---- 读配置：install.ps1 会生成 config.ps1，里面写着 v2rayN 装在哪 ----
$V2rayNDir        = $null
$EnableKillSwitch = $true                  # 开机时自动打开断网保护（config.ps1 里可以关掉）
$CheckUpdate      = $true                  # 每天查一次有没有新版本，只提醒不安装（config.ps1 里可以关掉）
$ConfigFile = Join-Path $PSScriptRoot 'config.ps1'
if (Test-Path $ConfigFile) { . $ConfigFile }
$V2rayNExe  = if ($V2rayNDir) { Join-Path $V2rayNDir 'v2rayN.exe' } else { $null }

# ---- 从 v2rayN 自己的配置里读端口和 TUN 开关 ----
# v2rayN 的几个端口都是从"本地端口"往后数的：
#   本地端口 +0  代理入口（系统代理、浏览器连的就是它）
#   本地端口 +4  xray 的流量统计（气泡的网速从这里读）
#   本地端口 +6  sing-box 的 API（气泡的延迟从这里读）
$V2Port = 10808
$V2Tun  = $false
if ($V2rayNDir) {
    try {
        $guiCfg = Get-Content (Join-Path $V2rayNDir 'guiConfigs\guiNConfig.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($guiCfg.Inbound -and $guiCfg.Inbound[0].LocalPort) { $V2Port = [int]$guiCfg.Inbound[0].LocalPort }
        $V2Tun = [bool]$guiCfg.TunModeItem.EnableTun
    } catch { }
}
$StatsPort = $V2Port + 4
$ApiPort   = $V2Port + 6

# v2rayN 用 sing-box 开 TUN 时，网卡名字和地址段是固定的
$TunName = 'singbox_tun'
$TunNet  = '172.18.0.0/30'

# ---- 小工具 ----
# 往日志里记一行（断网保护、切模式这些重要操作都记一笔，出问题时好查）
function Write-Log($msg) {
    "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg | Add-Content -Path $LogFile -Encoding UTF8
}

# 当前是不是管理员（改防火墙、注册计划任务都需要）
function Test-Admin {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 某个本机端口有没有程序在监听（很快，几毫秒）
function Test-Listening($port) {
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    [bool]($listeners | Where-Object { $_.Port -eq $port })
}

# 头像：文件夹里放一张 avatar.png / avatar.jpg 就会用上，没有也能正常跑
function Get-AvatarFile {
    Get-ChildItem $PSScriptRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq 'avatar' -and $_.Extension -match '^\.(png|jpe?g)$' } | Select-Object -First 1
}

# 在右下角弹一条 Windows 通知；有头像的话，左边显示圆形头像
#   Show-Toast '标题' '正文'           普通通知，几秒后自己收起
#   Show-Toast '标题' '正文' -Alarm    警报：循环响铃、一直停在屏幕上，必须点「知道了」
function Show-Toast($title, $message, [switch]$Alarm) {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    $t = [System.Security.SecurityElement]::Escape($title)
    $m = [System.Security.SecurityElement]::Escape($message)

    $img = ''
    $logo = Get-AvatarFile
    if ($logo) {
        $src = [System.Security.SecurityElement]::Escape(([System.Uri]$logo.FullName).AbsoluteUri)
        $img = "<image placement='appLogoOverride' hint-crop='circle' src='$src'/>"
    }

    if ($Alarm) {
        # scenario='alarm'：不会自动消失；循环播放闹钟声；"知道了"是系统自带的关闭按钮
        $head  = "<toast scenario='alarm' duration='long'>"
        $extra = "<audio src='ms-winsoundevent:Notification.Looping.Alarm2' loop='true'/>" +
                 "<actions><action content='知道了' arguments='dismiss' activationType='system'/></actions>"
    } else {
        $head  = "<toast>"
        $extra = ''
    }

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml("$head<visual><binding template='ToastGeneric'>$img<text>$t</text><text>$m</text></binding></visual>$extra</toast>")
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
}
