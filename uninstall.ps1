# uninstall.ps1 —— 一键卸载，把电脑恢复原样
# 做的事：关掉气泡 → 删掉计划任务 → 防火墙出站改回"默认放行" → 删掉本工具建的防火墙规则
# 不会动 v2rayN 本身，也不会关掉 Windows 防火墙（防火墙开着本来就是对的）
#
# 用法：右键「开始」→「终端(管理员)」，然后：
#   cd 这个文件夹的路径
#   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

$here = $PSScriptRoot
. "$here\common.ps1"

if (-not (Test-Admin)) {
    Write-Host '需要管理员权限：右键「开始」→「终端(管理员)」，再运行一次。' -ForegroundColor Yellow
    exit 1
}

# 1. 关掉气泡
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$(Join-Path $here 'bubble.ps1')*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host '已关闭气泡'

# 2. 删掉计划任务，再删掉空的任务文件夹
Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
try {
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $svc.GetFolder('\').DeleteFolder($AppName, 0)
} catch { }
Write-Host "已删除计划任务 $TaskFolder"

# 3. 防火墙：出站改回默认放行（Windows 的默认设置），再删掉本工具建的规则
Set-NetFirewallProfile -Profile Domain, Private, Public -DefaultOutboundAction Allow
Remove-NetFirewallRule -Group $KsGroup    -ErrorAction SilentlyContinue
Remove-NetFirewallRule -Group $BlockGroup -ErrorAction SilentlyContinue
Write-Host '已恢复防火墙：出站默认放行，本工具的规则都删掉了'
Write-Log '已卸载'

if (Test-Path $ModeFile) { Remove-Item $ModeFile }

Write-Host ''
Write-Host '卸载完成。这个文件夹现在可以直接删掉了。' -ForegroundColor Green
