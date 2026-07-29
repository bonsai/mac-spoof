# tray.ps1 — タスクトレイ常駐 (MAC spoof管理)
# 起動: powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\tray.ps1"

# ロガー起動 (最優先)
$log = "$env:USERPROFILE\tray-debug.log"
function log { $msg = "[$(Get-Date -Format 'HH:mm:ss')] $args" ; $msg | Out-File -Append -FilePath $log ; Write-Host $msg }

log "=== START ==="

# 起動通知 (最初だけ)
$startMsg = $true

# ---- .NET読込 ----
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    log "Add-Type OK"
} catch {
    log "Add-Type FAILED: $_"
    break
}

# ---- アイコンファイル ----
$icoPath = "$env:USERPROFILE\tray.ico"
log "icoPath: $icoPath (exists=$(Test-Path $icoPath))"

# ---- フォーム (非表示) ----
try {
    $form = New-Object System.Windows.Forms.Form
    $form.WindowState = "Minimized"
    $form.ShowInTaskbar = $false
    $form.add_Load({ $form.Hide() })
    log "Form created"
} catch {
    log "Form FAILED: $_"
}

# ---- WiFi情報 ----
function Get-WiFiStatus {
    $info = @{ MAC = "?"; SSID = "?"; Signal = "?" }
    try {
        $a = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($a) { $info.MAC = $a.MacAddress }
        $iface = netsh wlan show interfaces
        foreach ($line in $iface) {
            if ($line -match 'SSID\s*:\s*(.+)')    { $info.SSID = $matches[1].Trim() }
            if ($line -match 'Signal\s*:\s*(\d+)%') { $info.Signal = $matches[1] + "%" }
        }
        log "WiFi: MAC=$($info.MAC) SSID=$($info.SSID)"
    } catch { log "WiFi FAILED: $_" }
    return $info
}

# ---- タスクトレイアイコン ----
try {
    $tray = New-Object System.Windows.Forms.NotifyIcon
    log "NotifyIcon created"
    
    if (Test-Path $icoPath) {
        $tray.Icon = [System.Drawing.Icon]::new($icoPath)
        log "Icon loaded from file"
    } else {
        $tray.Icon = [System.Drawing.SystemIcons]::Information
        log "Icon: fallback Information"
    }
    
    $tray.Visible = $true
    $tray.Text = "mac-spoof"
    log "tray.Visible=$($tray.Visible)  tray.Text=$($tray.Text)"
} catch {
    log "NotifyIcon FAILED: $_"
}

# ---- タイマー ----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000
$timer.Add_Tick({
    $info = Get-WiFiStatus
    $remain = 45 - (([DateTime]::Now.Hour * 60 + [DateTime]::Now.Minute) % 45)
    if ($remain -eq 45) { $remain = 0 }
    $mac = $info.MAC; if ($mac.Length -gt 17) { $mac = $mac.Substring(0, 17) }
    $ssid = $info.SSID; if ($ssid.Length -gt 13) { $ssid = $ssid.Substring(0, 13) }
    $tray.Text = "$mac $ssid ${remain}m"
})

# ---- メニュー ----
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
    $remain = 45 - (([DateTime]::Now.Hour * 60 + [DateTime]::Now.Minute) % 45)
    if ($remain -eq 45) { $remain = 0 }
    $next = [DateTime]::Now.AddMinutes($remain)
    [System.Windows.Forms.MessageBox]::Show(
        "MAC:  $($info.MAC)`nSSID: $($info.SSID)`nSig:  $($info.Signal)",
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
log "Menu set"

# ---- 初回更新 ----
$info = Get-WiFiStatus
$tray.Text = "$($info.MAC) $($info.SSID)"
$timer.Start()

log "=== Calling Application.Run(form) ==="

# 初回のみ確認ポップアップ
if ($startMsg) {
    [System.Windows.Forms.MessageBox]::Show(
        "mac-spoof tray icon running.`nLook for red/yellow circle near clock.",
        "mac-spoof", "OK", "Information")
    $startMsg = $false
}

try {
    [System.Windows.Forms.Application]::Run($form)
    log "Application.Run returned (script exiting)"
} catch {
    log "Application.Run FAILED: $_"
}

log "=== END ==="
