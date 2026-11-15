# install.ps1 —— 一键安装
# 做的事：找到 v2rayN → 生成 config.ps1 → 注册计划任务（开机自启 + 气泡右键菜单要用的几个）→ 马上启动
# 重复运行也没关系（更新到新版本后再跑一次就行）
#
# 用法：右键「开始」按钮 →「终端(管理员)」，然后：
#   cd 这个文件夹的路径
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# 也可以直接告诉它 v2rayN 在哪：
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 -V2rayNDir 'D:\v2rayN-windows-64'

param([string]$V2rayNDir)
$dirArg = $V2rayNDir                  # 先存起来：下面 . common.ps1 会覆盖同名变量
$here   = $PSScriptRoot
. "$here\common.ps1"

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# ---- 0. 要管理员权限（注册"以最高权限运行"的计划任务、改防火墙都需要）----
if (-not (Test-Admin)) {
    Say '需要管理员权限：右键「开始」→「终端(管理员)」，再运行一次。' Yellow
    exit 1
}

# ---- 1. 从 GitHub 下载的文件会被 Windows 标记成"来自网络"，解除标记，计划任务才能正常跑 ----
Get-ChildItem $here -File | Unblock-File

# ---- 2. 找 v2rayN ----
function Test-V2rayNDir($dir) { $dir -and (Test-Path (Join-Path $dir 'v2rayN.exe')) }

function Find-V2rayN {
    # a) 正在运行的 v2rayN
    $p = Get-Process v2rayN -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -First 1
    if ($p) { return Split-Path $p.Path }
    # b) 上次安装时记下的
    if (Test-V2rayNDir $V2rayNDir) { return $V2rayNDir }
    # c) 常见位置找一找：各个盘的前两层 + 桌面/下载/文档的前三层
    $roots  = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' -and (Test-Path $_.Root) } |
                ForEach-Object { @{ Path = $_.Root; Depth = 2 } })
    $roots += foreach ($f in 'Desktop', 'Downloads', 'Documents') { @{ Path = Join-Path $env:USERPROFILE $f; Depth = 3 } }
    foreach ($r in $roots) {
        $hit = Get-ChildItem $r.Path -Filter 'v2rayN.exe' -Recurse -Depth $r.Depth -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.DirectoryName }
    }
    return $null
}

if ($dirArg) {
    $dir = $dirArg.Trim('"', ' ')
} else {
    Say '正在找 v2rayN...'
    $dir = Find-V2rayN
    if ($dir) {
        Say "找到了：$dir"
        $ans = Read-Host '是这个吗？直接回车 = 是，或者输入正确的文件夹路径'
        if ($ans.Trim()) { $dir = $ans.Trim('"', ' ') }
    } else {
        $dir = (Read-Host '没找到 v2rayN。请输入 v2rayN 所在的文件夹（里面有 v2rayN.exe）').Trim('"', ' ')
    }
}
if (-not (Test-V2rayNDir $dir)) {
    Say "这个文件夹里没有 v2rayN.exe：$dir" Red
    exit 1
}
$dir = (Resolve-Path $dir).Path

# ---- 3. 要不要断网保护 ----
Say ''
Say '断网保护：代理一掉线，就用防火墙拦住所有直连，防止用中国 IP 连上国外账号。' Cyan
Say '  开着的时候，只有 v2rayN、走 TUN 的流量、局域网能联网；代理断了就整台电脑断网（这正是它的作用）。' Cyan
Say '  需要临时直连时（比如登录校园网），右键气泡就能临时关掉。' Cyan
$ks = Read-Host '开机自动开启断网保护吗？直接回车 = 开启，输入 n = 不开'
$ksValue = if ($ks.Trim() -match '^[nN]') { '$false' } else { '$true' }

# ---- 4. 写 config.ps1 ----
$config = @"
# config.ps1 —— 由 install.ps1 生成，可以直接改；改完重新运行 install.ps1（或重启电脑）生效

# v2rayN 所在的文件夹（里面有 v2rayN.exe）
`$V2rayNDir = '$($dir.Replace("'", "''"))'

# 开机时自动打开断网保护（代理掉线时拦住直连，防止中国 IP 泄露）
# 改成 `$false 就不自动开；之后也可以随时在气泡右键菜单里手动开关
`$EnableKillSwitch = $ksValue
"@
[System.IO.File]::WriteAllText($ConfigFile, $config, (New-Object System.Text.UTF8Encoding $true))
Say "已写入 $ConfigFile" Green

# 名单：第一次安装时从模板复制一份，以后改 sensitive-apps.txt 就行
$apps = Join-Path $here 'sensitive-apps.txt'
if (-not (Test-Path $apps)) {
    Copy-Item (Join-Path $here 'sensitive-apps.example.txt') $apps
    Say "已生成 $apps（直连模式要封锁的程序名单，可以自己改）" Green
}

# 重新读一次设置（拿到新的 v2rayN 路径、端口、TUN 开关）
. "$here\common.ps1"
if (-not $V2Tun) {
    Say ''
    Say '提示：v2rayN 现在没开 TUN 模式。' Yellow
    Say '  不开 TUN 时，只有走系统代理的程序才会走代理；断网保护开着的话，其他程序都会被拦下连不了网。' Yellow
    Say '  建议在 v2rayN 主界面底部打开「启用 Tun」。' Yellow
}

# ---- 5. 注册计划任务 ----
# 为什么用计划任务：开机自启要管理员权限（v2rayN 开 TUN、改防火墙都需要），计划任务可以"以最高权限运行"而不弹 UAC
# conhost --headless：让 PowerShell 在后台跑，不闪黑窗口
$user = "$env:USERDOMAIN\$env:USERNAME"
function Register-AppTask($name, $file, $extraArgs = '', [switch]$AtLogOn, $delay, [switch]$Limited) {
    $arg    = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $here $file)`" $extraArgs".Trim()
    $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument $arg
    $level  = if ($Limited) { 'Limited' } else { 'Highest' }
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $level
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    $params = @{ TaskPath = $TaskFolder; TaskName = $name; Action = $action; Principal = $principal; Settings = $settings; Force = $true }
    if ($AtLogOn) {
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        if ($delay) { $trigger.Delay = $delay }
        $params.Trigger = $trigger
    }
    Register-ScheduledTask @params | Out-Null
    Say "  计划任务 $TaskFolder$name" Green
}
Say ''
Say '注册计划任务：'
Register-AppTask 'auto-proxy'     'auto-proxy.ps1' -AtLogOn                         # 开机：开保护 → 启动 v2rayN → 测网
Register-AppTask 'bubble'         'bubble.ps1'     -AtLogOn -Delay 'PT10S' -Limited  # 开机 10 秒后：气泡（普通权限就够）
Register-AppTask 'killswitch-on'  'killswitch.ps1' '-Mode On'                       # 下面四个给气泡右键菜单用
Register-AppTask 'killswitch-off' 'killswitch.ps1' '-Mode Off'
Register-AppTask 'mode-direct'    'mode.ps1'       '-Mode Direct'
Register-AppTask 'mode-proxy'     'mode.ps1'       '-Mode Proxy'

# ---- 6. 马上跑起来 ----
# 旧版本的气泡还开着的话先关掉，换成新的
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$(Join-Path $here 'bubble.ps1')*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-ScheduledTask -TaskPath $TaskFolder -TaskName 'auto-proxy'
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskPath $TaskFolder -TaskName 'bubble'

Say ''
Say '装好了！右下角会出现气泡，几秒后弹出"代理已就绪"的通知。' Green
Say '  · 想换头像：把一张图片命名为 avatar.png（或 avatar.jpg）放进这个文件夹'
Say '  · 不想用了：用管理员终端运行 uninstall.ps1，会把防火墙和计划任务都恢复原样'
