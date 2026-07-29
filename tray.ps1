# tray.ps1 — Windows タスクトレイ常駐 (MAC spoof管理)
#
# 起動方法 (管理者PowerShell):
#   powershell -ExecutionPolicy Bypass -File tray.ps1
#
# スタートアップ登録:
#   powershell -ExecutionPolicy Bypass -Command "& {
#     $wsh = New-Object -ComObject WScript.Shell
#     $shortcut = $wsh.CreateShortcut('~\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\mac-spoof-tray.lnk')
#     $shortcut.TargetPath = 'powershell.exe'
#     $shortcut.Arguments = '-WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\PATH\TO\tray.ps1"'
#     $shortcut.Save()
#   }"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 設定
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RotateScript = Join-Path $ScriptDir "wifi-mac-rotate.ps1"
$IntervalMs = 10000  # 更新間隔(ms)

# ---- 計算: 次回45分rotate時刻 ----
function Get-NextRotateTime {
    $now = [DateTime]::Now
    $min = $now.Minute
    $hour = $now.Hour

    # 45分サイクルの残り時間を計算
    # 基準: 00:00, 00:45, 01:30, 02:15, 03:00, 03:45 ...
    $totalMin = $hour * 60 + $min
    $phase = $totalMin % 45
    $remain = 45 - $phase
    if ($remain -eq 45) { $remain = 0 }

    return $now.AddMinutes($remain)
}

# ---- 現在のWiFi情報取得 ----
function Get-WiFiStatus {
    $info = @{ MAC = "N/A"; SSID = "N/A"; Signal = "N/A" }

    try {
        $adapter = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($adapter) {
            $info.MAC = $adapter.MacAddress
        }

        $iface = netsh wlan show interfaces
        foreach ($line in $iface) {
            if ($line -match 'SSID\s*:\s*(.+)') { $info.SSID = $matches[1].Trim() }
            if ($line -match 'Signal\s*:\s*(\d+)%') { $info.Signal = $matches[1] + "%" }
        }
    } catch {}

    return $info
}

# ---- タスクトレイアイコン作成 ----
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Text = "mac-spoof"
$tray.Icon = [System.Drawing.SystemIcons]::Information
$tray.Visible = $true

# タイマー (定期更新)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $IntervalMs

$timer.Add_Tick({
    $info = Get-WiFiStatus
    $next = Get-NextRotateTime
    $remain = [math]::Round(($next - [DateTime]::Now).TotalMinutes, 1)

    $tray.Text = "MAC: $($info.MAC)`nSSID: $($info.SSID)`nRotate: ${remain}min"
    $tray.BalloonTipTitle = "mac-spoof"
    $tray.BalloonTipText = "MAC: $($info.MAC)`nSSID: $($info.SSID)`nSignal: $($info.Signal)"
})

# ---- コンテキストメニュー ----
$menu = New-Object System.Windows.Forms.ContextMenuStrip

# Rotate Now
$itemRotate = New-Object System.Windows.Forms.ToolStripMenuItem
$itemRotate.Text = "Rotate Now"
$itemRotate.Add_Click({
    $tray.BalloonTipTitle = "mac-spoof"
    $tray.BalloonTipText = "Rotating MAC..."
    $tray.ShowBalloonTip(3000)

    try {
        if (Test-Path $RotateScript) {
            $result = powershell -ExecutionPolicy Bypass -File $RotateScript 2>&1
            $tray.BalloonTipText = "MAC changed! Check status."
        } else {
            # Try via WSL
            $result = wsl /home/sexy/MEGA/tools/wifi-mac-rotate.sh cron 2>&1
            $tray.BalloonTipText = "WSL rotate triggered."
        }
        $tray.ShowBalloonTip(3000)
    } catch {
        $tray.BalloonTipText = "Rotate failed: $_"
        $tray.ShowBalloonTip(5000)
    }
})
$menu.Items.Add($itemRotate) | Out-Null

# Show Status
$itemStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$itemStatus.Text = "Show Status"
$itemStatus.Add_Click({
    $info = Get-WiFiStatus
    $next = Get-NextRotateTime
    $remain = [math]::Round(($next - [DateTime]::Now).TotalMinutes, 1)

    $msg = @"
MAC:     $($info.MAC)
SSID:    $($info.SSID)
Signal:  $($info.Signal)
Next:    $($next.ToString('HH:mm')) (${remain}min)
"@
    [System.Windows.Forms.MessageBox]::Show($msg, "mac-spoof", "OK", "Information")
})
$menu.Items.Add($itemStatus) | Out-Null

# Separator
$menu.Items.Add("-") | Out-Null

# Exit
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
