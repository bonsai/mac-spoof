# tray.ps1 — Windows タスクトレイ常駐 (MAC spoof管理)
# 起動: powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\tray.ps1"

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    $err = "Failed to load .NET assemblies: $_"
    [System.Windows.Forms.MessageBox]::Show($err, "mac-spoof error", "OK", "Error")
    exit 1
}

$IntervalMs = 10000

function Get-NextRotateTime {
    $now = [DateTime]::Now
    $remain = 45 - (($now.Hour * 60 + $now.Minute) % 45)
    if ($remain -eq 45) { $remain = 0 }
    return $now.AddMinutes($remain)
}

function Get-WiFiStatus {
    $info = @{ MAC = "N/A"; SSID = "N/A"; Signal = "N/A" }
    try {
        $a = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($a) { $info.MAC = $a.MacAddress }
        $iface = netsh wlan show interfaces
        foreach ($line in $iface) {
            if ($line -match 'SSID\s*:\s*(.+)')    { $info.SSID = $matches[1].Trim() }
            if ($line -match 'Signal\s*:\s*(\d+)%') { $info.Signal = $matches[1] + "%" }
        }
    } catch {}
    return $info
}

# ---- アイコン ----
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.SystemIcons]::Information
$tray.Visible = $true

# ツールチップ (63文字制限)
$timerUpdate = {
    $info = Get-WiFiStatus
    $next = Get-NextRotateTime
    $remain = [math]::Round(($next - [DateTime]::Now).TotalMinutes, 1)
    $mac = $info.MAC
    if ($mac.Length -gt 11) { $mac = $mac.Substring(0, 11) + ".." }
    $ssid = $info.SSID
    if ($ssid.Length -gt 12) { $ssid = $ssid.Substring(0, 12) + ".." }
    $tray.Text = "$mac $ssid ${remain}m"
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $IntervalMs
$timer.Add_Tick({
    & $timerUpdate
    $info = Get-WiFiStatus
    $tray.BalloonTipTitle = "mac-spoof"
    $tray.BalloonTipText = "MAC: $($info.MAC)`nSSID: $($info.SSID)`nSignal: $($info.Signal)"
})

# ---- メニュー ----
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$itemRotate = New-Object System.Windows.Forms.ToolStripMenuItem
$itemRotate.Text = "Rotate Now"
$itemRotate.Add_Click({
    $tray.BalloonTipTitle = "mac-spoof"
    $tray.BalloonTipText = "Rotating MAC..."
    $tray.ShowBalloonTip(2000)
    try {
        wsl /home/sexy/MEGA/tools/wifi-mac-rotate.sh cron 2>&1 | Out-Null
        $tray.BalloonTipText = "MAC rotated!"
    } catch {
        $tray.BalloonTipText = "Rotate failed"
    }
    $tray.ShowBalloonTip(3000)
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
