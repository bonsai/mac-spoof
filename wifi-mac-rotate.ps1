#!/usr/bin/env pwsh
<#
.SYNOPSIS
    MAC address spoofing via registry (Disable/Enable method)
.DESCRIPTION
    Changes Wi-Fi adapter MAC address by writing a random locally-administered
    MAC to the registry NetworkAddress key, then toggling the adapter.
    This is more reliable than Set-NetAdapter -MacAddress which fails on many drivers.
.PARAMETER Status
    Print current MAC only and exit.
.PARAMETER Quiet
    Minimal output (designed for cron usage).
.PARAMETER NewMac
    Specify a custom MAC to use (auto-generated if omitted).
#>

param(
    [switch]$Status,
    [switch]$Quiet,
    [string]$NewMac = ""
)

$wifiName = "Wi-Fi"

# ---------- Admin check ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if (-not $Quiet) { Write-Error "Admin privileges required" }
    exit 1
}

# ---------- Get adapter ----------
$adapter = Get-NetAdapter -Name $wifiName -ErrorAction SilentlyContinue
if (-not $adapter) {
    if (-not $Quiet) { Write-Error "Adapter '$wifiName' not found" }
    exit 1
}

$currentMac = $adapter.MacAddress

if ($Status) {
    Write-Output $currentMac
    exit 0
}

# ---------- Generate or use given MAC ----------
if ($NewMac -ne "" -and $NewMac -match '^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$') {
    $newMacHex = $NewMac -replace '[-:]', ''
    $newMacDash = $NewMac -replace ':', '-'
} else {
    $bytes = @(0..5 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
    $bytes[0] = ($bytes[0] -bor 0x02) -band 0xFE  # locally administered + unicast
    $newMacHex = ($bytes | ForEach-Object { "{0:X2}" -f $_ }) -join ""
    $newMacDash = ($bytes | ForEach-Object { "{0:X2}" -f $_ }) -join "-"
}

if (-not $Quiet) {
    Write-Output "OLD: $currentMac"
    Write-Output "NEW: $newMacDash"
}

# ---------- Find registry key ----------
$classGuid = "{4d36e972-e325-11ce-bfc1-08002be10318}"
$regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$classGuid"
$driverDesc = $adapter.DriverDescription
$targetKey = $null

Get-ChildItem $regBase -ErrorAction SilentlyContinue | ForEach-Object {
    $desc = (Get-ItemProperty -Path $_.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
    if ($desc -eq $driverDesc) {
        $targetKey = $_.PSPath
    }
}

if (-not $targetKey) {
    if (-not $Quiet) { Write-Error "Registry key not found for: $driverDesc" }
    exit 1
}

# ---------- Write NetworkAddress ----------
Set-ItemProperty -Path $targetKey -Name "NetworkAddress" -Value $newMacHex
if (-not $Quiet) { Write-Output "REG: wrote NetworkAddress = $newMacHex" }

# ---------- Toggle adapter (triggers driver re-read of NetworkAddress) ----------
Disable-NetAdapter -Name $wifiName -Confirm:$false
Start-Sleep -Seconds 2
Enable-NetAdapter -Name $wifiName -Confirm:$false
Start-Sleep -Seconds 6

# ---------- Verify ----------
$updated = Get-NetAdapter -Name $wifiName
$resultMac = $updated.MacAddress
$resultStatus = $updated.Status

if (-not $Quiet) {
    Write-Output "MAC: $resultMac"
    Write-Output "STATUS: $resultStatus"
}

if ($resultMac -ne $newMacDash) { exit 2 }   # MAC mismatch
if ($resultStatus -ne "Up")    { exit 3 }    # not connected

exit 0
