# tray.ps1 — Windows タスクトレイ常駐 (MAC spoof管理)
#
# 起動方法 (管理者PowerShell):
#   powershell -ExecutionPolicy Bypass -File tray.ps1
#
# スタートアップ登録:
#   powershell -ExecutionPolicy Bypass -Command "& {
#     $wsh = New-Object -ComObject WScript.Shell
#     $s = $wsh.CreateShortcut('~\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\mac-spoof-tray.lnk')
#     $s.TargetPath = 'powershell.exe'
#     $s.Arguments = '-WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\tray.ps1"'
#     $s.Save()
#   }"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$IntervalMs = 10000

# ---- 次回45分rotate時刻 ----
function Get-NextRotateTime {
    $now = [DateTime]::Now
    $totalMin = $now.Hour * 60 + $now.Minute
    $remain = 45 - ($totalMin % 45)
    if ($remain -eq 45) { $remain = 0 }
    return $now.AddMinutes($remain)
}

# ---- WiFi情報取得 ----
function Get-WiFiStatus {
    $info = @{ MAC = "N/A"; SSID = "N/A"; Signal = "N/A" }
    try {
        $a = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($a) { $info.MAC = $a.MacAddress }
        $iface = netsh wlan show interfaces
        foreach ($line in $iface) {
            if ($line -match 'SSID\s*:\s*(.+)')   { $info.SSID = $matches[1].Trim() }
            if ($line -match 'Signal\s*:\s*(\d+)%') { $info.Signal = $matches[1] + "%" }
        }
    } catch {}
    return $info
}

# ---- アイコン作成 ----
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Text = "mac-spoof"
$tray.Icon = [System.Drawing.SystemIcons]::Information
$tray.Visible = $true

# タイマー
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $IntervalMs
$timer.Add_Tick({
    $info = Get-WiFiStatus
    $next = Get-NextRotateTime
    $remain = [math]::Round(($next - [DateTime]::Now).TotalMinutes, 1)
    $tray.Text = "MAC: $($info.MAC)`nSSID: $($info.SSID)`nrotate: ${remain}min"
    $tray.BalloonTipTitle = "mac-spoof"
    $tray.BalloonTipText = "MAC: $($info.MAC)`nSSID: $($info.SSID)`nSignal: $($info.Signal)"
})

# ---- コンテキストメニュー ----
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$itemRotate = New-Object System.Windows.Forms.ToolStripMenuItem
$itemRotate.Text = "Rotate Now"
$itemRotate.Add_Click({
    $tray.BalloonTipTitle = "mac-spoof"
    $tray.BalloonTipText = "Rotating MAC..."
    $tray.ShowBalloonTip(2000)
    try {
        $result = wsl /home/sexy/MEGA/tools/wifi-mac-rotate.sh cron 2>&1
        $tray.BalloonTipText = "MAC rotated!"
        $tray.ShowBalloonTip(2000)
    } catch {
        $tray.BalloonTipText = "Failed: $_"
        $tray.ShowBalloonTip(5000)
    }
})
$menu.Items.Add($itemRotate) | Out-Null

$itemStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$itemStatus.Text = "Show Status"
$itemStatus.Add_Click({
    $info = Get-WiFiStatus
    $next = Get-NextRotateTime
    $remain = [math]::Round(($next - [DateTime]::Now).TotalMinutes, 1)
    [System.Windows.Forms.MessageBox]::Show(
        "MAC:     $($info.MAC)`nSSID:    $($info.SSID)`nSignal:  $($info.Signal)`nNext:    $($next.ToString('HH:mm')) (${remain}min)",
        "mac-spoof", "OK", "Information")
})
$menu.Items.Add($itemStatus) | Out-Null

$menu.Items.Add("-") | Out-Null

$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem
$itemExit.Text = "Exit"
$itemExit.Add_Click({
    $timer.Stop()
    $tray.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})
$menu.Items.Add($itemExit) | Out-Null

$tray.ContextMenuStrip = $menu

# ---- 初回表示 ----
$info = Get-WiFiStatus
$tray.BalloonTipTitle = "mac-spoof"
$tray.BalloonTipText = "MAC: $($info.MAC)`nSSID: $($info.SSID)"
$tray.ShowBalloonTip(3000)

# ---- 起動 ----
$timer.Start()
[System.Windows.Forms.Application]::Run()
