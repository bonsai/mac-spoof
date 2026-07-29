# tray.ps1 — タスクトレイ常駐
# 起動: powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\tray.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- フォーム (非表示・メッセージポンプ) ----
$form = New-Object System.Windows.Forms.Form
$form.WindowState = "Minimized"
$form.ShowInTaskbar = $false
$form.add_Load({ $form.Hide() })

# ---- WiFi情報取得 ----
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

# ---- タスクトレイアイコン ----
$tray = New-Object System.Windows.Forms.NotifyIcon
$icoPath = Join-Path $PSScriptRoot "tray.ico"
if (Test-Path $icoPath) {
    $tray.Icon = [System.Drawing.Icon]::new($icoPath)
} else {
    $tray.Icon = [System.Drawing.SystemIcons]::Information
}
$tray.Visible = $true
$tray.Text = "mac-spoof"

# ---- 更新タイマー ----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000
$timer.Add_Tick({
    $info = Get-WiFiStatus
    $next = [DateTime]::Now.AddMinutes(45 - (($Now.Hour * 60 + $Now.Minute) % 45))
    $remain = [math]::Round(($next - [DateTime]::Now).TotalMinutes, 1)
    $mac = $info.MAC; if ($mac.Length -gt 17) { $mac = $mac.Substring(0, 17) }
    $ssid = $info.SSID; if ($ssid.Length -gt 13) { $ssid = $ssid.Substring(0, 13) + ".." }
    $tray.Text = "$mac $ssid ${remain}m"
})

# ---- 右クリックメニュー ----
$menu = New-Object System.Windows.Forms.ContextMenuStrip

$itemRotate = New-Object System.Windows.Forms.ToolStripMenuItem
$itemRotate.Text = "Rotate Now"
$itemRotate.Add_Click({
    $tray.BalloonTipTitle = "mac-spoof"
    $tray.BalloonTipText = "Rotating..."
    $tray.ShowBalloonTip(2000)
    try { wsl /home/sexy/MEGA/tools/wifi-mac-rotate.sh cron 2>&1 | Out-Null; $tray.BalloonTipText = "Done!" } catch { $tray.BalloonTipText = "Failed" }
    $tray.ShowBalloonTip(3000)
})
$menu.Items.Add($itemRotate) | Out-Null

$itemStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$itemStatus.Text = "Show Status"
$itemStatus.Add_Click({
    $info = Get-WiFiStatus
    $next = [DateTime]::Now.AddMinutes(45 - (($Now.Hour * 60 + $Now.Minute) % 45))
    $remain = [math]::Round(($next - [DateTime]::Now).TotalMinutes, 1)
    [System.Windows.Forms.MessageBox]::Show(
        "MAC:  $($info.MAC)`nSSID: $($info.SSID)`nSig:  $($info.Signal)`nNext: $($next.ToString('HH:mm')) (${remain}m)",
        "mac-spoof")
})
$menu.Items.Add($itemStatus) | Out-Null
$menu.Items.Add("-") | Out-Null

$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem
$itemExit.Text = "Exit"
$itemExit.Add_Click({
    $timer.Stop()
    $tray.Visible = $false
    $tray.Dispose()
    $form.Close()
})
$menu.Items.Add($itemExit) | Out-Null

$tray.ContextMenuStrip = $menu

# ---- 初回表示 ----
$info = Get-WiFiStatus
$tray.Text = "$($info.MAC) $($info.SSID)"
$tray.BalloonTipTitle = "mac-spoof"
$tray.BalloonTipText = "Ready"
$tray.ShowBalloonTip(2000)
$timer.Start()

# ---- 起動 (フォームでメッセージポンプ) ----
[System.Windows.Forms.Application]::Run($form)
