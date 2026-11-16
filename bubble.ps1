# bubble.ps1 —— 桌面悬浮气泡

. "$PSScriptRoot\common.ps1"     # 把 common.ps1 里的设置和函数"贴"进来

# 同一时间只允许一个气泡：已经有一个在跑了，就直接退出
$mutex = New-Object System.Threading.Mutex($false, "Local\$AppName-bubble")
try   { $gotLock = $mutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $gotLock = $true }   # 上一个气泡被强制关掉时锁会"被遗弃"，直接接手
if (-not $gotLock) { exit }

Add-Type -AssemblyName PresentationFramework
$startedAt = Get-Date            # 刚启动的 30 秒内不报掉线（开机时 v2rayN 可能还没起来）

# ---- 外观参数：想调大小改这里 ----
$bubbleSize = 76                     # 圆的直径
$glowSpace  = 16                     # 圆外面留给发光的空间
$winSize    = $bubbleSize + 2 * $glowSpace
$panelWidth = 300                    # 悬停面板的宽度
$sparkW     = $panelWidth - 36       # 网速曲线的宽度（面板宽 - 左右内边距）
$sparkH     = 46                     # 网速曲线的高度

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="$winSize" Height="$winSize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize">
    <Grid x:Name="Root" RenderTransformOrigin="0.5,0.5">
        <Grid.RenderTransform>
            <ScaleTransform ScaleX="1" ScaleY="1"/>
        </Grid.RenderTransform>

        <!-- 外圈：状态灯 + 发光 -->
        <Ellipse x:Name="Ring" Width="$bubbleSize" Height="$bubbleSize"
                 Fill="#202020" Stroke="#9E9E9E" StrokeThickness="4">
            <Ellipse.Effect>
                <DropShadowEffect Color="#9E9E9E" BlurRadius="20" ShadowDepth="0" Opacity="1"/>
            </Ellipse.Effect>
        </Ellipse>

        <!-- 头像：文件夹里有 avatar.png/jpg 就填进来，没有就显示一个"咲"字 -->
        <Ellipse x:Name="Avatar" Width="$($bubbleSize - 8)" Height="$($bubbleSize - 8)"/>
        <TextBlock x:Name="Placeholder" Text="咲" Foreground="#DDDDDD" FontSize="28"
                   HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,0,0,6"/>

        <!-- 底部小胶囊：延迟数字 -->
        <Border x:Name="Pill" HorizontalAlignment="Center" VerticalAlignment="Bottom"
                Margin="0,0,0,$($glowSpace - 6)" Padding="7,1" CornerRadius="9"
                Background="#E6202020" BorderBrush="#9E9E9E" BorderThickness="1.5">
            <TextBlock x:Name="Label" Text="..." Foreground="White" FontSize="12" FontWeight="SemiBold"/>
        </Border>

        <!-- 悬停面板：鼠标移到气泡上时弹出来 -->
        <Popup x:Name="Panel" Placement="Left" HorizontalOffset="-6" AllowsTransparency="True"
               PopupAnimation="Fade" StaysOpen="True">
            <Border Margin="14" Width="$panelWidth" CornerRadius="14" Padding="18,14"
                    Background="#F2181A1F" BorderBrush="#33FFFFFF" BorderThickness="1" IsHitTestVisible="False">
                <Border.Effect>
                    <DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.55"/>
                </Border.Effect>
                <StackPanel TextElement.FontFamily="Microsoft YaHei UI">

                    <!-- 第一行：状态 + 出口位置 -->
                    <DockPanel>
                        <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
                            <Ellipse x:Name="StatusDot" Width="9" Height="9" Fill="#9E9E9E" VerticalAlignment="Center"/>
                            <TextBlock x:Name="StatusText" Text="检测中" Foreground="#EEEEEE" FontSize="13"
                                       FontWeight="SemiBold" Margin="7,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock x:Name="LocText" Text="出口查询中..." Foreground="#9AA0A6" FontSize="12"
                                   HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </DockPanel>

                    <!-- 大号网速 -->
                    <Grid Margin="0,12,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="↓ 下载" Foreground="#9AA0A6" FontSize="11"/>
                            <TextBlock x:Name="DownText" Text="--" Foreground="#4FC3F7" FontSize="22" FontWeight="SemiBold"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="↑ 上传" Foreground="#9AA0A6" FontSize="11"/>
                            <TextBlock x:Name="UpText" Text="--" Foreground="#CE93D8" FontSize="22" FontWeight="SemiBold"/>
                        </StackPanel>
                    </Grid>

                    <!-- 最近 60 秒下载曲线 -->
                    <Canvas Width="$sparkW" Height="$sparkH" Margin="0,8,0,0" ClipToBounds="True">
                        <Polygon  x:Name="SparkFill" Fill="#334FC3F7"/>
                        <Polyline x:Name="Spark" Stroke="#4FC3F7" StrokeThickness="1.6" StrokeLineJoin="Round"/>
                    </Canvas>
                    <TextBlock x:Name="SparkCaption" Text="最近 60 秒" Foreground="#6B7178" FontSize="10" Margin="0,2,0,0"/>

                    <Border Height="1" Background="#26FFFFFF" Margin="0,10,0,10"/>

                    <!-- 详细信息 -->
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="72"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Grid.Column="0" Text="新建连接" Foreground="#9AA0A6" FontSize="12" Margin="0,2"/>
                        <TextBlock Grid.Row="1" Grid.Column="0" Text="复用连接" Foreground="#9AA0A6" FontSize="12" Margin="0,2"/>
                        <TextBlock Grid.Row="2" Grid.Column="0" Text="出口 IP"  Foreground="#9AA0A6" FontSize="12" Margin="0,2"/>
                        <TextBlock Grid.Row="3" Grid.Column="0" Text="断网保护" Foreground="#9AA0A6" FontSize="12" Margin="0,2"/>
                        <TextBlock Grid.Row="4" Grid.Column="0" Text="直连检测" Foreground="#9AA0A6" FontSize="12" Margin="0,2"/>
                        <TextBlock Grid.Row="5" Grid.Column="0" Text="本次流量" Foreground="#9AA0A6" FontSize="12" Margin="0,2"/>
                        <TextBlock Grid.Row="6" Grid.Column="0" Text="持续"     Foreground="#9AA0A6" FontSize="12" Margin="0,2"/>
                        <TextBlock x:Name="DelayText" Grid.Row="0" Grid.Column="1" Text="--" Foreground="#EEEEEE" FontSize="12" Margin="0,2"/>
                        <TextBlock x:Name="WarmText"  Grid.Row="1" Grid.Column="1" Text="--" Foreground="#EEEEEE" FontSize="12" Margin="0,2"/>
                        <TextBlock x:Name="IpText"    Grid.Row="2" Grid.Column="1" Text="--" Foreground="#EEEEEE" FontSize="12" Margin="0,2"/>
                        <TextBlock x:Name="KsText"    Grid.Row="3" Grid.Column="1" Text="--" Foreground="#EEEEEE" FontSize="12" Margin="0,2" TextWrapping="Wrap"/>
                        <TextBlock x:Name="LeakText"  Grid.Row="4" Grid.Column="1" Text="--" Foreground="#EEEEEE" FontSize="12" Margin="0,2" TextWrapping="Wrap"/>
                        <TextBlock x:Name="TotalText" Grid.Row="5" Grid.Column="1" Text="--" Foreground="#EEEEEE" FontSize="12" Margin="0,2"/>
                        <TextBlock x:Name="SinceText" Grid.Row="6" Grid.Column="1" Text="--" Foreground="#EEEEEE" FontSize="12" Margin="0,2"/>
                    </Grid>

                    <TextBlock Text="点一下气泡打开 ip.sb · 右键切换直连 / 断网保护 / 退出" Foreground="#6B7178" FontSize="10" Margin="0,12,0,0"/>
                    <TextBlock x:Name="VersionText" Text="" Foreground="#6B7178" FontSize="10" Margin="0,3,0,0"/>
                </StackPanel>
            </Border>
        </Popup>
    </Grid>
</Window>
"@

$window      = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ring        = $window.FindName('Ring')
$avatar      = $window.FindName('Avatar')
$placeholder = $window.FindName('Placeholder')
$pill        = $window.FindName('Pill')
$label       = $window.FindName('Label')
$glow        = $ring.Effect                              # 外圈的发光效果
$hoverScale  = $window.FindName('Root').RenderTransform  # 悬停放大用

# 面板里要更新的元素
$panel      = $window.FindName('Panel')
$statusDot  = $window.FindName('StatusDot')
$statusText = $window.FindName('StatusText')
$locText    = $window.FindName('LocText')
$downText   = $window.FindName('DownText')
$upText     = $window.FindName('UpText')
$spark      = $window.FindName('Spark')
$sparkFill  = $window.FindName('SparkFill')
$sparkCap   = $window.FindName('SparkCaption')
$delayText  = $window.FindName('DelayText')
$warmText   = $window.FindName('WarmText')
$ipText     = $window.FindName('IpText')
$ksText     = $window.FindName('KsText')
$leakText   = $window.FindName('LeakText')
$totalText  = $window.FindName('TotalText')
$sinceText  = $window.FindName('SinceText')
$versionText = $window.FindName('VersionText')
$panel.PlacementTarget = $ring

# ---- 头像 ----
$avatarFile = Get-AvatarFile
if ($avatarFile) {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.UriSource        = New-Object System.Uri $avatarFile.FullName
    $bmp.CacheOption      = 'OnLoad'     # 读进内存就松开文件，之后能随时替换图片
    $bmp.DecodePixelWidth = 256          # 只解码到 256 像素宽，省内存
    $bmp.EndInit()
    $imgBrush = New-Object System.Windows.Media.ImageBrush $bmp
    $imgBrush.Stretch = 'UniformToFill'  # 等比缩放、裁掉多出来的部分，正好填满圆
    $avatar.Fill = $imgBrush
    $placeholder.Visibility = 'Collapsed'
}

# 放到屏幕右下角（任务栏上面）
$area = [System.Windows.SystemParameters]::WorkArea
$window.Left = $area.Right  - $window.Width  - 10
$window.Top  = $area.Bottom - $window.Height - 10

# 按住拖动；没拖动（原地点一下）就打开 ip.sb
$window.Add_MouseLeftButtonDown({
    $panel.IsOpen = $false               # 拖动时先收起面板，不然它会留在原地
    $oldLeft = $window.Left
    $oldTop  = $window.Top
    $window.DragMove()
    $moved = [math]::Abs($window.Left - $oldLeft) + [math]::Abs($window.Top - $oldTop)
    if ($moved -lt 3) {
        Start-Process 'https://ip.sb'
    }
})

# ---- 小动画 ----
# 悬停时轻轻放大一点
function Start-Scale($to) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.To       = $to
    $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150))
    $hoverScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $anim)
    $hoverScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $anim)
}
# 鼠标进来：放大 + 打开面板；出去：恢复 + 收起
$window.Add_MouseEnter({ Start-Scale 1.08; Update-Panel; $panel.IsOpen = $true })
$window.Add_MouseLeave({ Start-Scale 1.0;  $panel.IsOpen = $false })

# 危险时外圈的光"呼吸"：亮度和光晕大小一起一涨一落
$breathing = $false
function Start-Breathing {
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From           = 0.2
    $fade.To             = 1.0
    $fade.Duration       = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(700))
    $fade.AutoReverse    = $true
    $fade.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $grow = $fade.Clone()            # 同样的节奏，只改起止值
    $grow.From = 4
    $grow.To   = 32
    $glow.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::OpacityProperty, $fade)
    $glow.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::BlurRadiusProperty, $grow)
}
function Stop-Breathing {
    $glow.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::OpacityProperty, $null)
    $glow.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::BlurRadiusProperty, $null)
    $glow.Opacity    = 1
    $glow.BlurRadius = 20
}

# ---- 断网保护：读状态 + 开关 ----
# 防火墙三个配置文件都"开启 + 出站默认拦截"才算开着（直接读注册表，不需要管理员，很快）
function Get-KillSwitchOn {
    foreach ($p in 'DomainProfile', 'StandardProfile', 'PublicProfile') {
        $key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\$p"
        if ([Microsoft.Win32.Registry]::GetValue($key, 'EnableFirewall', 0) -ne 1)        { return $false }
        if ([Microsoft.Win32.Registry]::GetValue($key, 'DefaultOutboundAction', 0) -ne 1) { return $false }
    }
    return $true
}
$ksOn        = $null       # $null = 还没读过
$ksCountdown = 0           # 每 5 秒读一次

# 右键菜单：断网保护开关 + 退出
$menu = New-Object System.Windows.Controls.ContextMenu
$ksItem = New-Object System.Windows.Controls.MenuItem
$ksItem.Add_Click({
    if ($script:ksOn) {
        $msg = "关闭后，代理一旦掉线，程序就会用你的中国 IP 直连出去。`n`n" +
               "一般只在登录校园网认证页这类时候临时关一下，用完记得打开（下次开机也会自动打开）。`n`n" +
               "确定要临时关闭吗？"
        $ans = [System.Windows.MessageBox]::Show($msg, '临时关闭断网保护', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
        $task = 'killswitch-off'
    } else {
        $task = 'killswitch-on'
    }
    try {
        Start-ScheduledTask -TaskPath $TaskFolder -TaskName $task -ErrorAction Stop   # 计划任务以管理员身份去改防火墙
        $script:ksCountdown = 2                                                      # 2 秒后重新读状态
    } catch {
        [System.Windows.MessageBox]::Show("没找到计划任务 $TaskFolder$task，是不是还没运行 install.ps1？`n`n$($_.Exception.Message)", '断网保护', 'OK', 'Error') | Out-Null
    }
})
[void]$menu.Items.Add($ksItem)

# 模式切换：代理 ⇄ 直连（打游戏）
$modeItem = New-Object System.Windows.Controls.MenuItem
$modeItem.Add_Click({
    if ($script:appMode -eq 'direct') {
        Start-ScheduledTask -TaskPath $TaskFolder -TaskName 'mode-proxy' -ErrorAction SilentlyContinue
        return
    }
    # ① 名单里的程序必须先全部关掉
    $running = Get-RunningSensitive
    if ($running.Count -gt 0) {
        $list = ($running | Group-Object ProcessName | ForEach-Object { "  • $($_.Name)（$($_.Count) 个进程）" }) -join "`n"
        $msg = "切到直连之前，这些程序要先关掉：`n`n$list`n`n" +
               "点「是」：我帮你关（先正常关闭，关不掉的强制结束。Claude 被关掉的话，跟 Claude 的对话也会断开）`n" +
               "点「否」：你自己去关，关完再来切"
        $ans = [System.Windows.MessageBox]::Show($msg, '切到直连模式', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        foreach ($p in $running) { if ($p.MainWindowHandle -ne 0) { [void]$p.CloseMainWindow() } }   # 先礼貌地关窗口
        Start-Sleep -Seconds 3
        Get-RunningSensitive | Stop-Process -Force -ErrorAction SilentlyContinue                    # 还在的（后台进程）强制结束
        Start-Sleep -Milliseconds 800
        $left = Get-RunningSensitive
        if ($left.Count -gt 0) {
            [System.Windows.MessageBox]::Show("还有关不掉的：$(($left | ForEach-Object ProcessName | Select-Object -Unique) -join '、')。`n先手动关掉再切。", '切到直连模式', 'OK', 'Warning') | Out-Null
            return
        }
    }
    # ② 再确认一次
    $msg = "切到直连后：`n`n" +
           "  • v2rayN 会退出，所有流量走你自己的网络（游戏延迟更低）`n" +
           "  • 名单里的程序会被防火墙封锁，就算打开了也连不了网`n" +
           "  • 断网保护暂停`n`n" +
           "打完游戏记得右键气泡切回代理（重启电脑也会自动切回）。确定切换吗？"
    $ans = [System.Windows.MessageBox]::Show($msg, '切到直连模式', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    try { Start-ScheduledTask -TaskPath $TaskFolder -TaskName 'mode-direct' -ErrorAction Stop }
    catch { [System.Windows.MessageBox]::Show("没找到计划任务 $($TaskFolder)mode-direct，是不是还没运行 install.ps1？`n`n$($_.Exception.Message)", '切到直连模式', 'OK', 'Error') | Out-Null }
})
[void]$menu.Items.Add($modeItem)

# 有新版本时才出现：打开 GitHub 的发布页，让你自己看改了什么、决定要不要更新
$updateItem = New-Object System.Windows.Controls.MenuItem
$updateItem.Visibility = 'Collapsed'
$updateItem.Add_Click({ Start-Process "https://github.com/$RepoSlug/releases/latest" })
[void]$menu.Items.Add($updateItem)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$exitItem = New-Object System.Windows.Controls.MenuItem
$exitItem.Header = '退出气泡'
$exitItem.Add_Click({ $window.Close() })
[void]$menu.Items.Add($exitItem)
$window.ContextMenu = $menu
$window.Add_ContextMenuOpening({
    $panel.IsOpen = $false
    if ($script:ksOn) { $ksItem.Header = '断网保护：开启中 ✓（点击临时关闭）' }
    else              { $ksItem.Header = '断网保护：已关闭 ⚠（点击开启）' }
    if ($script:appMode -eq 'direct') {
        $modeItem.Header     = '🛡 切回代理模式'
        $ksItem.Visibility   = 'Collapsed'          # 直连模式下保护本来就是暂停的，不显示这个开关
    } else {
        $modeItem.Header     = '🎮 切到直连模式（打游戏）'
        $ksItem.Visibility   = 'Visible'
    }
    if ($script:updateVersion) {
        $updateItem.Header     = "⬆ 查看新版本 $($script:updateVersion)（你现在是 v$AppVersion）"
        $updateItem.Visibility = 'Visible'
    } else {
        $updateItem.Visibility = 'Collapsed'
    }
})

# ---- 格式化小工具 ----
# 每秒多少字节 → 人看得懂的网速
function Format-Speed($bytesPerSec) {
    if ($bytesPerSec -ge 1MB)     { '{0:N1} MB/s' -f ($bytesPerSec / 1MB) }
    elseif ($bytesPerSec -ge 1KB) { '{0:N0} KB/s' -f ($bytesPerSec / 1KB) }
    else                          { '{0:N0} B/s'  -f $bytesPerSec }
}
# 字节总数 → KB / MB / GB
function Format-Bytes($bytes) {
    if ($bytes -ge 1GB)     { '{0:N2} GB' -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { '{0:N1} MB' -f ($bytes / 1MB) }
    else                    { '{0:N0} KB' -f ($bytes / 1KB) }
}
# 一段时间 → "2 小时 5 分" / "3 分 20 秒"
function Format-Duration($span) {
    if ($span.TotalHours -ge 1)       { '{0} 小时 {1} 分' -f [int][math]::Floor($span.TotalHours), $span.Minutes }
    elseif ($span.TotalMinutes -ge 1) { '{0} 分 {1} 秒' -f $span.Minutes, $span.Seconds }
    else                              { '{0} 秒' -f $span.Seconds }
}

# xray 的流量计数器
$statsUrl = "http://127.0.0.1:$StatsPort/debug/vars"
$web = New-Object System.Net.WebClient
$web.Proxy = $null          # 问的是本机，别绕去代理
$lastUp = -1                # -1 表示"还没读过"
$lastDown = -1
$speedClock = [System.Diagnostics.Stopwatch]::StartNew()
$downRate = 0               # 当前下载速度（字节/秒）
$upRate   = 0
$sessionDown = 0            # 气泡开着以来，走代理一共下载了多少
$sessionUp   = 0
$history = New-Object 'System.Collections.Generic.Queue[double]'   # 最近 60 秒的下载速度

# ---- 延迟：优先让 sing-box 自己测；sing-box 没在跑（比如没开 TUN）就自己通过代理测 ----
Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.UseProxy = $false
$http = [System.Net.Http.HttpClient]::new($handler)
$http.Timeout = [TimeSpan]::FromSeconds(8)

$testUrl  = 'https://www.google.com/generate_204'
$delayUrl = "http://127.0.0.1:$ApiPort/proxies/proxy/delay?url=$([uri]::EscapeDataString($testUrl))&timeout=5000"

# 自己测：请求一次、掐表。计时放在 C# 里做，因为气泡每秒才看一次结果，在 PowerShell 这边掐表只能精确到秒
Add-Type -ReferencedAssemblies System.Net.Http -TypeDefinition @'
using System.Diagnostics;
using System.Net.Http;
using System.Threading.Tasks;
public static class DelayProbe {
    public static async Task<long> Measure(HttpClient client, string url) {
        var sw = Stopwatch.StartNew();
        using (var resp = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false)) {
            resp.EnsureSuccessStatusCode();     // 不是 2xx 就算失败
        }
        return sw.ElapsedMilliseconds;
    }
    // 复用连接的延迟：先请求一次把连接建好（不计时），再在同一条连接上计时第二次
    public static async Task<long> MeasureWarm(HttpClient client, string url) {
        using (var first = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false)) {
            first.EnsureSuccessStatusCode();
        }
        return await Measure(client, url).ConfigureAwait(false);
    }
}
'@
$probeHandler = New-Object System.Net.Http.HttpClientHandler
$probeHandler.Proxy    = New-Object System.Net.WebProxy("http://127.0.0.1:$V2Port")
$probeHandler.UseProxy = $true
$httpProbe = [System.Net.Http.HttpClient]::new($probeHandler)
$httpProbe.Timeout = [TimeSpan]::FromSeconds(6)
$httpProbe.DefaultRequestHeaders.ConnectionClose = $true    # 每次都新建连接，跟 sing-box 的测法一样（"新建连接"延迟）

# 复用连接的延迟（跟 v2rayN 列表里的数字接近）：连接保持不断，只算一个来回。只用来显示，不影响掉线判断
$warmHandler = New-Object System.Net.Http.HttpClientHandler
$warmHandler.Proxy    = New-Object System.Net.WebProxy("http://127.0.0.1:$V2Port")
$warmHandler.UseProxy = $true
$httpWarm = [System.Net.Http.HttpClient]::new($warmHandler)
$httpWarm.Timeout = [TimeSpan]::FromSeconds(6)
$warmTask      = $null
$warmCountdown = 5         # 启动 5 秒后测第一次，之后每 10 秒一次
$warmMs        = $null

$delayTask      = $null    # 正在进行的那次测试（"订单号"），没有就是 $null
$delayKind      = 'api'    # 这次是谁测的：api = sing-box 测的，self = 自己测的
$delayCountdown = 0        # 还剩几秒发起下一次，0 = 马上测
$lastMs         = $null    # 最近一次测到的延迟；测不通时是 $null

# ---- 直连检测：不指定代理，直接问 Cloudflare"你看我在哪" ----
# 代理正常时流量会被 TUN 接走 → 看到的是节点的国家；要是看到 CN，说明有流量在用中国 IP 直连
$leakTask      = $null
$leakCountdown = 3
$leakCN        = $false    # 当前是不是检测到了中国 IP
$leakLine      = '检测中...'

# 换状态颜色：外圈、发光、胶囊边框一起变
function Set-RingColor($hex) {
    $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    $solid = New-Object System.Windows.Media.SolidColorBrush $color
    $ring.Stroke      = $solid
    $pill.BorderBrush = $solid
    $glow.Color       = $color
}

# ---- 掉线提醒：状态机 ----
$tunMode     = $V2Tun       # v2rayN 开着 TUN 的话，TUN 网卡也必须在（common.ps1 从 v2rayN 设置里读的）
$netState    = 'unknown'    # unknown / ok / down
$stateSince  = Get-Date     # 当前状态从什么时候开始
$failStreak  = 0            # 连续测不通几次了
$missingSecs = 0            # 核心进程连续不见了几秒
$missingText = ''           # 哪几个进程不见了
$tunGoneSecs = 0            # TUN 网卡连续不见了几秒
$downSince   = $null        # 什么时候开始断的
$downSilent  = $false       # 这次掉线发生在启动宽限期里、没弹通知 → 恢复时也别弹

# ---- 模式：proxy（代理）/ direct（直连，打游戏用）----
# mode.ps1 和 auto-proxy.ps1 会把当前模式写进 mode.txt（路径 $ModeFile 在 common.ps1 里），气泡每秒看一眼
$appMode        = 'proxy'
$modeChangedAt  = Get-Date
$sensitiveNames = @()       # 名单里的进程名（从 sensitive-apps.txt 读）
$sensitiveSeen  = @()       # 直连模式下，上一次看到开着的敏感程序
$watchCountdown = 0

# 名单 → 进程名（只要文件名，比如 claude、chrome）
function Get-SensitiveNames {
    @(Get-Content (Join-Path $PSScriptRoot 'sensitive-apps.txt') -Encoding UTF8 -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } |
      ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } | Select-Object -Unique)
}
function Get-RunningSensitive {
    $names = Get-SensitiveNames
    if ($names.Count -eq 0) { return @() }
    @(Get-Process -Name $names -ErrorAction SilentlyContinue)
}

# 切换模式时，把状态清干净
function Enter-Mode($m) {
    $script:appMode       = $m
    $script:modeChangedAt = Get-Date
    if ($m -eq 'direct') {
        $script:sensitiveNames = Get-SensitiveNames
        $script:sensitiveSeen  = @()
        $script:watchCountdown = 0
    } else {
        # 刚切回代理：v2rayN 正在启动，重置所有状态，并给 30 秒宽限期
        $script:startedAt   = Get-Date
        $script:netState    = 'unknown'; $script:stateSince = Get-Date
        $script:failStreak  = 0; $script:lastMs = $null; $script:warmMs = $null; $script:warmCountdown = 5
        $script:missingSecs = 0; $script:tunGoneSecs = 0
        $script:leakCN      = $false
        $script:lastUp      = -1; $script:lastDown = -1
        $script:delayCountdown = 3; $script:ipCountdown = 5; $script:leakCountdown = 8
        $label.Text = '...'; Set-RingColor '#9E9E9E'                 # 先变回灰色"检测中"，别一直挂着"直连"
    }
}

# 直连模式下每 2 秒看一眼：有没有名单里的程序被打开了
function Watch-Sensitive {
    $script:watchCountdown--
    if ($script:watchCountdown -gt 0) { return }
    $script:watchCountdown = 2
    $now = @()
    if ($script:sensitiveNames.Count -gt 0) {
        $now = @(Get-Process -Name $script:sensitiveNames -ErrorAction SilentlyContinue | ForEach-Object ProcessName | Select-Object -Unique)
    }
    $new = @($now | Where-Object { $script:sensitiveSeen -notcontains $_ })
    if ($new.Count -gt 0) {
        Show-Toast '⚠ 直连模式下打开了敏感程序' "$($new -join '、') 已被防火墙封锁、连不了网。要用它的话，先右键气泡切回代理"
    }
    $script:sensitiveSeen = $now
}

# 只有状态真的变了才动作，所以不会刷屏
function Set-NetState($newState, $reason) {
    if ($newState -eq $script:netState) { return }
    $oldState = $script:netState
    $script:netState   = $newState
    $script:stateSince = Get-Date
    if ($newState -eq 'down') {
        $script:downSince = Get-Date
        $justStarted = ((Get-Date) - $script:startedAt).TotalSeconds -lt 30
        $script:downSilent = ($oldState -eq 'unknown' -and $justStarted)
        if (-not $script:downSilent) {                               # 开机 / 刚切回代理那会儿由 auto-proxy 负责报告
            if ($script:ksOn) {
                Show-Toast '代理掉线了 ✗' "$reason。断网保护开着，直连已被拦住，中国 IP 漏不出去"
            } else {
                Show-Toast '⚠ 代理掉线，可能正在直连！' "$reason。断网保护是关着的，程序可能在用中国 IP 直连，赶紧处理" -Alarm
            }
        }
    } elseif ($newState -eq 'ok' -and $oldState -eq 'down') {
        if (-not $script:downSilent) {
            $secs = [int]((Get-Date) - $script:downSince).TotalSeconds
            Show-Toast '代理恢复了 ✓' "断了 $secs 秒，$reason"
        }
        $script:leakCountdown = 2                                    # 恢复后马上再查一次直连
    }
}

# 根据当前所有状态，决定外圈颜色、胶囊文字、要不要呼吸（危险程度从高到低判断）
function Update-Ring {
    if ($script:appMode -eq 'direct') {
        # 直连模式：蓝色实线，安安静静，不呼吸
        $label.Text = '直连'; Set-RingColor '#42A5F5'
        $ring.StrokeDashArray = $null
        if ($script:breathing) { Stop-Breathing; $script:breathing = $false }
        return
    }
    if ($script:leakCN) {
        $label.Text = 'CN'; Set-RingColor '#F44336'
    } elseif ($script:netState -eq 'down') {
        $label.Text = '×'; Set-RingColor '#F44336'
    } elseif ($script:failStreak -gt 0) {
        $label.Text = '?'; Set-RingColor '#FFC107'
    } elseif ($script:lastMs -ne $null) {
        $label.Text = "$($script:lastMs)"
        if ($script:lastMs -lt 500)      { Set-RingColor '#4CAF50' }
        elseif ($script:lastMs -lt 1500) { Set-RingColor '#FFC107' }
        else                             { Set-RingColor '#F44336' }
    }
    # 断网保护关着时，外圈变成虚线，一眼就能看出来
    if ($script:ksOn -eq $false) { $ring.StrokeDashArray = [System.Windows.Media.DoubleCollection]::Parse('2.5 1.5') }
    else                         { $ring.StrokeDashArray = $null }

    $danger = $script:leakCN -or $script:netState -eq 'down'
    if ($danger -and -not $script:breathing)     { Start-Breathing; $script:breathing = $true }
    elseif (-not $danger -and $script:breathing) { Stop-Breathing;  $script:breathing = $false }
}

# ---- 出口 IP：通过代理问 ip.sb ----
$proxyHandler = New-Object System.Net.Http.HttpClientHandler
$proxyHandler.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:$V2Port")
$proxyHandler.UseProxy = $true
$httpViaProxy = [System.Net.Http.HttpClient]::new($proxyHandler)
$httpViaProxy.Timeout = [TimeSpan]::FromSeconds(10)

# 国家代码 → 中文名
$countryNames = @{
    KR = '韩国'; JP = '日本'; US = '美国'; HK = '香港'; TW = '台湾'
    SG = '新加坡'; GB = '英国'; DE = '德国'; FR = '法国'; CA = '加拿大'
    CN = '中国'; RU = '俄罗斯'; AU = '澳大利亚'; NL = '荷兰'
}

# ---- 检查更新：每天问一次 GitHub 最新发布的版本，只提醒、不自动安装 ----
# 为什么不自动安装：这套脚本是以管理员身份运行的，要是哪天仓库被人动了手脚，自动更新会把坏代码直接装到所有人电脑上
$updHandler = New-Object System.Net.Http.HttpClientHandler
$updHandler.Proxy    = New-Object System.Net.WebProxy("http://127.0.0.1:$V2Port")
$updHandler.UseProxy = $true
$httpUpdate = [System.Net.Http.HttpClient]::new($updHandler)
$httpUpdate.Timeout = [TimeSpan]::FromSeconds(15)
$httpUpdate.DefaultRequestHeaders.UserAgent.ParseAdd("$AppName/$AppVersion")   # GitHub 的接口要求必须带 User-Agent
$updateApi       = "https://api.github.com/repos/$RepoSlug/releases/latest"
$updateTask      = $null
$updateCountdown = 60      # 启动 1 分钟后查第一次（开机时代理可能还没好）
$updateVersion   = $null   # 发现的新版本号（比如 v1.1.0），没有新版本就是 $null
$updateNotified  = $null   # 这个版本已经弹过通知了，同一次运行里不重复弹

$ipTask      = $null
$ipCountdown = 0           # 0 = 一启动就查
$locLine     = '出口查询中...'
$ipLine      = '--'

# ---- 把最新数据画到面板上（只在面板开着时调用，省得白算）----
function Update-Panel {
    # 最底下一行：版本号；有新版本时变成黄色提示
    if ($script:updateVersion) {
        $versionText.Text = "v$AppVersion · 有新版本 $($script:updateVersion)，右键气泡查看"
        $versionText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FFC107'))
    } else {
        $versionText.Text = "v$AppVersion"
    }
    if ($script:appMode -eq 'direct') {
        $statusText.Text = '🎮 直连模式（打游戏）'
        $statusDot.Fill  = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#42A5F5'))
        $locText.Text    = '不走代理'
        $downText.Text   = '--'; $upText.Text = '--'
        $delayText.Text  = '直连不测'
        $warmText.Text   = '直连不测'
        $ipText.Text     = '你自己的网络'
        $ksText.Text     = '暂停（直连模式）'
        if ($script:sensitiveSeen.Count -gt 0) { $leakText.Text = "⚠ $($script:sensitiveSeen -join '、') 开着（已封锁）" }
        else                                   { $leakText.Text = "名单里 $($script:sensitiveNames.Count) 个程序已封锁 ✓" }
        $totalText.Text  = "↓ $(Format-Bytes $script:sessionDown)    ↑ $(Format-Bytes $script:sessionUp)"
        $sinceText.Text  = "已直连 $(Format-Duration ((Get-Date) - $script:modeChangedAt))"
        $sparkCap.Text   = '直连模式下不统计网速'
        return
    }
    # 状态：中国 IP > 掉线 > 不太稳 > 正常 > 检测中
    if ($script:leakCN) {
        $txt = '⚠ 检测到中国 IP 直连'; $hex = '#F44336'
    } elseif ($script:netState -eq 'down') {
        $txt = '已掉线'; $hex = '#F44336'
        if ($script:missingText) { $txt = "已掉线 · $($script:missingText) 不见了" }
        elseif ($script:tunGoneSecs -gt 0) { $txt = '已掉线 · TUN 网卡不见了' }
    } elseif ($script:failStreak -gt 0) { $txt = '有点不稳'; $hex = '#FFC107' }
    elseif ($script:netState -eq 'ok')  { $txt = '代理正常'; $hex = '#4CAF50' }
    else                                { $txt = '检测中';   $hex = '#9E9E9E' }
    $statusText.Text = $txt
    $statusDot.Fill  = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))

    $locText.Text  = $script:locLine
    $downText.Text = Format-Speed $script:downRate
    $upText.Text   = Format-Speed $script:upRate

    if ($script:lastMs -ne $null) { $delayText.Text = "$($script:lastMs) 毫秒 · 打开新网站时" }
    else                          { $delayText.Text = "测不通（连续 $($script:failStreak) 次）" }
    if ($script:warmMs -ne $null) { $warmText.Text  = "$($script:warmMs) 毫秒 · 连上以后" }
    else                          { $warmText.Text  = '--' }
    $ipText.Text = $script:ipLine
    if ($script:ksOn)              { $ksText.Text = '开启 ✓  代理断了也漏不出去' }
    elseif ($script:ksOn -eq $false) { $ksText.Text = '已关闭 ⚠  掉线时会直连' }
    else                           { $ksText.Text = '读取中...' }
    $leakText.Text  = $script:leakLine
    $totalText.Text = "↓ $(Format-Bytes $script:sessionDown)    ↑ $(Format-Bytes $script:sessionUp)"
    $stateName = @{ ok = '正常'; down = '掉线'; unknown = '检测' }[$script:netState]
    $sinceText.Text = "已$stateName $(Format-Duration ((Get-Date) - $script:stateSince))"

    # 网速曲线：最近 60 个点，最高点顶到画布上沿（至少按 100 KB/s 算，避免小波动被放得很夸张）
    $vals = $history.ToArray()
    $peak = 0; foreach ($v in $vals) { if ($v -gt $peak) { $peak = $v } }
    $scale = [math]::Max(100KB, $peak)
    $pts = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $vals.Count; $i++) {
        $x = $sparkW * (60 - $vals.Count + $i) / 59
        $y = $sparkH - 2 - ($vals[$i] / $scale) * ($sparkH - 6)
        $pts.Add((New-Object System.Windows.Point $x, $y))
    }
    $spark.Points = $pts
    $fill = $pts.Clone()
    if ($pts.Count -gt 0) {
        $fill.Add((New-Object System.Windows.Point $pts[$pts.Count - 1].X, $sparkH))
        $fill.Add((New-Object System.Windows.Point $pts[0].X, $sparkH))
    }
    $sparkFill.Points = $fill
    $sparkCap.Text = "最近 60 秒 · 最高 $(Format-Speed $peak)"
}

# 每秒执行一次的定时任务
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    # ⓐ 现在是什么模式（mode.ps1 / auto-proxy.ps1 写在 mode.txt 里）
    $m = 'proxy'
    try { $m = [System.IO.File]::ReadAllText($ModeFile).Trim() } catch { }
    if ($m -ne $script:appMode) { Enter-Mode $m }
    if ($script:appMode -eq 'direct') {
        # 直连模式：不测代理、不报掉线，只盯着名单里的程序有没有被打开
        Watch-Sensitive
        Update-Ring
        if ($panel.IsOpen) { Update-Panel }
        return
    }

    # ⓪ 进程和 TUN 网卡还在不在（每秒看一次）
    # 必须在：v2rayN 本体 + 至少一个核心；开着 TUN 的话 sing-box 必须在（v2rayN 用它开 TUN）
    $running = @(Get-Process -Name v2rayN, xray, sing-box, mihomo -ErrorAction SilentlyContinue | ForEach-Object ProcessName)
    $missing = @()
    if ($running -notcontains 'v2rayN') { $missing += 'v2rayN' }
    if ($tunMode) { if ($running -notcontains 'sing-box') { $missing += 'sing-box' } }
    elseif (@($running | Where-Object { $_ -ne 'v2rayN' }).Count -eq 0) { $missing += '代理核心' }
    if ($missing.Count -gt 0) { $script:missingSecs++ } else { $script:missingSecs = 0 }
    $script:missingText = $missing -join '、'
    if ($script:missingSecs -eq 4) { Set-NetState 'down' "进程不见了：$($script:missingText)" }

    if ($tunMode) {
        $tunUp = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                 Where-Object { $_.Name -eq $TunName -and $_.OperationalStatus -eq 'Up' }
        if ($tunUp) { $script:tunGoneSecs = 0 } else { $script:tunGoneSecs++ }
        if ($script:tunGoneSecs -eq 4) { Set-NetState 'down' 'TUN 网卡不见了' }
    }

    # ⓪b 断网保护开没开（每 5 秒读一次）
    $script:ksCountdown--
    if ($script:ksCountdown -le 0) {
        $now = Get-KillSwitchOn
        $settled = ((Get-Date) - $script:modeChangedAt).TotalSeconds -gt 20     # 刚切过模式，保护跟着变是正常的，不提示
        if ($script:ksOn -ne $null -and $now -ne $script:ksOn -and $settled) {
            if ($now) { Show-Toast '断网保护已开启 ✓' '代理断了也不会用中国 IP 直连出去' }
            else      { Show-Toast '断网保护已关闭 ⚠' '代理一旦掉线就会直连，用完记得打开（外圈变成虚线了）' }
        }
        $script:ksOn = $now
        $script:ksCountdown = 5
    }

    # ① 网速
    try {
        $proxyStats = ($web.DownloadString($statsUrl) | ConvertFrom-Json).stats.outbound.proxy
        $up   = $proxyStats.uplink
        $down = $proxyStats.downlink
        $sec  = $speedClock.Elapsed.TotalSeconds
        $speedClock.Restart()

        # 计数器变小了 = xray 重启了（多半是你换了节点），3 秒后重查出口
        if ($script:lastUp -ge 0 -and $up -lt $script:lastUp) {
            $script:ipCountdown = 3
        }

        if ($script:lastUp -ge 0) {
            $dUp   = [math]::Max(0, $up   - $script:lastUp)
            $dDown = [math]::Max(0, $down - $script:lastDown)
            $script:upRate      = $dUp   / $sec
            $script:downRate    = $dDown / $sec
            $script:sessionUp   += $dUp
            $script:sessionDown += $dDown
        }
        $script:lastUp   = $up
        $script:lastDown = $down
    } catch {
        $script:upRate = 0; $script:downRate = 0
    }
    $history.Enqueue($script:downRate)
    if ($history.Count -gt 60) { [void]$history.Dequeue() }

    # ② 延迟：上一次已经测完、倒计时也到了，就"下单"（马上返回，不等结果）
    if ($script:delayTask -eq $null) {
        $script:delayCountdown--
        if ($script:delayCountdown -le 0) {
            if (Test-Listening $ApiPort) {
                $script:delayKind = 'api'                                         # sing-box 在：让它测
                $script:delayTask = $http.GetStringAsync($delayUrl)
            } else {
                $script:delayKind = 'self'                                        # 不在：自己通过代理测
                $script:delayTask = [DelayProbe]::Measure($httpProbe, $testUrl)
            }
        }
    }

    # ③ 延迟：看一眼"送到没"，送到了就处理结果
    if ($script:delayTask -ne $null -and $script:delayTask.IsCompleted) {
        if ($script:delayTask.Status -ne 'RanToCompletion') {
            $script:failStreak++
            $script:lastMs = $null
            if ($script:failStreak -ge 2) { Set-NetState 'down' '连续 2 次测不通，节点可能挂了' }
        } else {
            $script:failStreak = 0
            if ($script:delayKind -eq 'api') { $script:lastMs = ($script:delayTask.Result | ConvertFrom-Json).delay }
            else                             { $script:lastMs = $script:delayTask.Result }
            if ($script:missingSecs -eq 0 -and $script:tunGoneSecs -eq 0) {
                Set-NetState 'ok' "现在延迟 $($script:lastMs) 毫秒"
            }
        }
        $script:delayTask = $null
        # 出问题时 4 秒就再测一次，好尽快发现恢复；正常时 8 秒
        if ($script:netState -eq 'down' -or $script:failStreak -gt 0) { $script:delayCountdown = 4 }
        else { $script:delayCountdown = 8 }
    }

    # ③b 复用连接的延迟：每 10 秒测一次，只用来显示
    if ($script:warmTask -eq $null) {
        $script:warmCountdown--
        if ($script:warmCountdown -le 0) {
            $script:warmTask = [DelayProbe]::MeasureWarm($httpWarm, $testUrl)
        }
    } elseif ($script:warmTask.IsCompleted) {
        if ($script:warmTask.Status -eq 'RanToCompletion') { $script:warmMs = $script:warmTask.Result }
        else                                               { $script:warmMs = $null }
        $script:warmTask = $null
        $script:warmCountdown = 10
    }

    # ④ 出口 IP：倒计时到了就"下单"
    if ($script:ipTask -eq $null) {
        $script:ipCountdown--
        if ($script:ipCountdown -le 0) {
            $script:ipTask = $httpViaProxy.GetStringAsync('https://api.ip.sb/geoip')
        }
    }

    # ⑤ 出口 IP：看一眼"送到没"
    if ($script:ipTask -ne $null -and $script:ipTask.IsCompleted) {
        if ($script:ipTask.Status -eq 'RanToCompletion') {
            $geo = $script:ipTask.Result | ConvertFrom-Json
            $country = $countryNames[$geo.country_code]
            if (-not $country) { $country = $geo.country }     # 表里没有就用英文名
            $script:locLine = "$country · $($geo.city)"
            $script:ipLine  = $geo.ip
            $script:ipCountdown = 1800                         # 30 分钟后再查
        } else {
            $script:locLine = '出口查询失败'
            $script:ipCountdown = 30
        }
        $script:ipTask = $null
    }

    # ⑥ 直连检测：每 20 秒一次
    # 没开 TUN 时不测：那样只有走系统代理的程序才走代理，这个检测本身就是直连的，一定会看到 CN（误报）
    if (-not $tunMode) {
        $script:leakLine = '没开 TUN，不检测'
    } elseif ($script:leakTask -eq $null) {
        $script:leakCountdown--
        if ($script:leakCountdown -le 0) {
            $script:leakTask = $http.GetStringAsync('https://1.1.1.1/cdn-cgi/trace')
        }
    }
    if ($script:leakTask -ne $null -and $script:leakTask.IsCompleted) {
        if ($script:leakTask.Status -eq 'RanToCompletion') {
            $loc = ([regex]::Match($script:leakTask.Result, '(?m)^loc=(\w+)')).Groups[1].Value
            if ($loc -eq 'CN') {
                $script:leakLine = 'CN ⚠  有流量在用中国 IP 直连！'
                if (-not $script:leakCN) {
                    Show-Toast '⚠ 出口是中国 IP！' '有流量正在用中国 IP 直连出去。先别用 Claude 等账号，检查 v2rayN 和 TUN' -Alarm
                }
                $script:leakCN = $true
            } else {
                $script:leakLine = "$loc ✓  没有直连"
                $script:leakCN = $false
            }
        } else {
            $script:leakLine = '连不上（代理断了，或者被保护拦下了）'
            $script:leakCN = $false
        }
        $script:leakTask = $null
        $script:leakCountdown = 20
    }

    # ⑦ 检查更新：每天一次（直连模式在上面就 return 了，不会查）
    if ($CheckUpdate) {
        if ($script:updateTask -eq $null) {
            $script:updateCountdown--
            if ($script:updateCountdown -le 0) {
                $script:updateTask = $httpUpdate.GetStringAsync($updateApi)
            }
        } elseif ($script:updateTask.IsCompleted) {
            $script:updateCountdown = 3600                               # 没查到（代理断了、还没发布过版本）：1 小时后再试
            if ($script:updateTask.Status -eq 'RanToCompletion') {
                $script:updateCountdown = 86400                          # 查到了：明天再查
                try {
                    $tag    = ($script:updateTask.Result | ConvertFrom-Json).tag_name
                    $latest = [version]($tag -replace '^[vV]', '')       # "v1.1.0" → 1.1.0，[version] 会按数字比大小（1.10 > 1.9）
                    if ($latest -gt [version]$AppVersion) {
                        $script:updateVersion = $tag
                        if ($script:updateNotified -ne $tag) {
                            Show-Toast "有新版本 $tag ⬆" "你现在是 v$AppVersion。右键气泡 →「查看新版本」，看看改了什么再决定要不要更新"
                            $script:updateNotified = $tag
                        }
                    } else {
                        $script:updateVersion = $null
                    }
                } catch { }                                              # 版本号格式看不懂就当没有
            }
            $script:updateTask = $null
        }
    }

    # ⑧ 刷新外观；面板开着才刷新面板
    Update-Ring
    if ($panel.IsOpen) { Update-Panel }
})
$timer.Start()
$window.ShowDialog() | Out-Null
