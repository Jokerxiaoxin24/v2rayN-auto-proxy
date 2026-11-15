# auto-proxy.ps1 自动启动 v2rayN 代理
# --By jokerxiaoxin

# 设置（v2rayN 装在哪、端口多少）和工具函数（Show-Toast 弹通知）都在 common.ps1 里，跟气泡共用一份
. "$PSScriptRoot\common.ps1"

# v2rayN 的路径：install.ps1 安装时写进 config.ps1
$v2rayPath = $V2rayNExe
if (-not $v2rayPath -or -not (Test-Path $v2rayPath)) {
    Show-Toast '找不到 v2rayN ✗' '路径不对或者还没安装：重新运行一次 install.ps1，或者改 config.ps1 里的 $V2rayNDir' -Alarm
    exit 1
}

# =====================Stage 0 先开断网保护====================
# 先把门关上再开代理：开机这几秒里，谁都别想用中国 IP 直连出去
# （就算上次临时关掉了保护，每次开机也会自动重新打开；不想要的话在 config.ps1 里把 $EnableKillSwitch 改成 $false）
if ($EnableKillSwitch) { & "$PSScriptRoot\killswitch.ps1" -Mode On | Out-Null }
# 保护开好以后，再拆掉直连模式留下的封锁规则，并记下"现在是代理模式"
# （顺序不能反：先拆封锁再开保护的话，中间会有一小段谁都能直连的空档）
Remove-NetFirewallRule -Group $BlockGroup -ErrorAction SilentlyContinue
Set-Content -Path $ModeFile -Value 'proxy' -Encoding ASCII

# =====================Stage 1 检查运行状态====================
# v2rayN 运行状态
$runningStatus = Get-Process -Name v2rayN -ErrorAction SilentlyContinue   

if($runningStatus) {
    Write-Host "v2rayN 已启动 (PID $($runningStatus.Id))"
} else {
    Write-Host "v2rayN 未启动，正在启动..."
    Start-Process -FilePath $v2rayPath -WorkingDirectory (Split-Path $v2rayPath)
}

# ====================Stage 2 等待代理端口就绪====================
$port         = $V2Port # 端口：从 v2rayN 的设置里读（默认 10808）
$timeoutLimit = 30000   # 超时时限 30000 毫秒 (30秒)
$interval     = 200     # 检查间隔 200 毫秒
$ready        = $false  # 准备状态

# 秒表
$sw = [System.Diagnostics.Stopwatch]::StartNew() 

# 开始检查
while($sw.ElapsedMilliseconds -lt $timeoutLimit) {
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    if ($listeners | Where-Object { $_.Port -eq $port }) {
        $ready = $true
        break
    }
    Start-Sleep -Milliseconds $interval
}

if ($ready) {
    Write-Host "端口 $port 已就绪（耗时$($sw.ElapsedMilliseconds) 毫秒）"
} else {
    Write-Host "已超时...请检查节点或端口！"
}

# ====================Stage 3 测试代理是否成功联通====================
# 国外测试网站 是国内直连打不开的 能通说明代理通了
$foreignUrls = @(
    'https://www.google.com/generate_204',
    'https://x.com/favicon.ico',
    'https://www.facebook.com/favicon.ico'
)

# 国内百度 如果这个不通说明网压根没连上
$domesticUrl = 'https://www.baidu.com/'

# 本地端口
$proxy = "http://127.0.0.1:$port"

# 测一个网站：通了返回延迟(毫秒)，没通返回 -1
function Test-Site($url) {
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-WebRequest -Uri $url -Proxy $proxy -UseBasicParsing -TimeoutSec 5 | Out-Null
        return $sw2.ElapsedMilliseconds
    } catch {
        return -1
    }
}

if ($ready) {
    $maxRounds = 4                                          # 最多测 4 轮
    for ($round = 1; $round -le $maxRounds; $round++) {    
        Write-Host "第 $round 轮："                     
        $okCount = 0
        $fastest = 99999
        foreach ($url in $foreignUrls) {
            $ms = Test-Site $url
            if ($ms -ge 0) {
                $okCount++
                if ($ms -lt $fastest) { $fastest = $ms }
                Write-Host "  通  $ms 毫秒  $url"
            } else {
                Write-Host "  断           $url"
            }
        }
        if ($okCount -gt 0) { break }                    # 通了就不用再测
        if ($round -lt $maxRounds) {                   
            Write-Host "  全断，5 秒后再试..."            
            Start-Sleep -Seconds 5                       
        }                                                
    }                                                   

    if ($okCount -gt 0) {
        Write-Host "代理就绪！$okCount/$($foreignUrls.Count) 个国外网站链接成功"
        Show-Toast '代理已就绪 ✓' "$okCount/$($foreignUrls.Count) 个国外网站链接成功，最快 $fastest 毫秒"  
    } elseif ((Test-Site $domesticUrl) -ge 0) {
        Write-Host "连接超时！节点或代理出问题了"
        Show-Toast '代理没通 ✗' '换个节点试试？'  
    } else {
        Write-Host "请检查网络！国内网站也未成功链接"
        Show-Toast '网还没连上' '检查一下 WiFi'  
    }
} else {
    Write-Host "端口超时，跳过联网测试"
    Show-Toast 'v2rayN' "等了 $($timeoutLimit / 1000) 秒，端口 $port 还没打开"   
}