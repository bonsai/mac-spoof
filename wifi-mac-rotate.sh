#!/usr/bin/env bash
# wifi-mac-rotate.sh — WSL wrapper for MAC spoofing with tsubame.db logging
#
# Usage:
#   ./wifi-mac-rotate.sh              Rotate MAC + log to DB
#   ./wifi-mac-rotate.sh status       Show current MAC/SSID
#   ./wifi-mac-rotate.sh cron         Quiet mode (for cron)
#   ./wifi-mac-rotate.sh --install    Install to /usr/local/bin
#
# Dependencies:
#   - powershell.exe (Windows, admin) — for MAC spoofing
#   - sqlite3 (WSL)                    — for DB logging
#   - tsubame-agent (optional)         — for scan trigger
#
# Environment variables:
#   TSUBAME_DB     Path to tsubame.db (default: ~/.wifi-mac-tracker/tsubame.db)
#   TSUBAME_META   Path to meta.json  (default: ~/.wifi-mac-tracker/tsubame-meta.json)
#   TSUBAME_BIN    Path to tsubame-agent binary (for --scan)
#   TSUBAME_PS     Path to wifi-mac-rotate.ps1 (default: same dir as this script)

set -euo pipefail

# --- Configurable paths ---
: "${TSUBAME_DB:=$HOME/.wifi-mac-tracker/tsubame.db}"
: "${TSUBAME_META:=$HOME/.wifi-mac-tracker/tsubame-meta.json}"
: "${TSUBAME_BIN:=$HOME/.local/bin/tsubame-agent}"
: "${TSUBAME_PS:=$(cd "$(dirname "$0")" && pwd)/wifi-mac-rotate.ps1}"
: "${TSUBAME_LOG:=$HOME/.wifi-mac-tracker/rotate.log}"

# --- Helpers ---
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$TSUBAME_LOG"
    echo "$msg"
}

get_windows_mac() {
    powershell.exe -Command "Get-NetAdapter -Name 'Wi-Fi' | Select-Object -ExpandProperty MacAddress" 2>/dev/null | tr -d '\r\n'
}

get_windows_ssid() {
    powershell.exe -Command "netsh wlan show interfaces | findstr 'SSID'" 2>/dev/null | head -1 | sed 's/.*SSID\s*:\s*//' | tr -d '\r\n'
}

get_windows_bssid() {
    powershell.exe -Command "netsh wlan show interfaces | findstr 'BSSID'" 2>/dev/null | head -1 | sed 's/.*BSSID\s*:\s*//' | tr -d '\r\n' | sed 's/^ *//'
}

# --- Parse args ---
case "${1:-}" in
    status)
        mac=$(get_windows_mac)
        ssid=$(get_windows_ssid)
        echo "MAC=$mac  SSID=$ssid"
        exit 0
        ;;
    cron)
        quiet="-Quiet"
        ;;
    --install)
        cp "$0" /usr/local/bin/wifi-mac-rotate
        cp "$TSUBAME_PS" /usr/local/bin/wifi-mac-rotate.ps1
        chmod +x /usr/local/bin/wifi-mac-rotate
        echo "Installed to /usr/local/bin/wifi-mac-rotate"
        exit 0
        ;;
esac

quiet="${quiet:-}"

# --- Before ---
OLD_MAC=$(get_windows_mac)
OLD_SSID=$(get_windows_ssid)
OLD_BSSID=$(get_windows_bssid)
log "BEFORE: MAC=$OLD_MAC  SSID=$OLD_SSID"

# --- Run PS spoof ---
set +e
PS_OUTPUT=$(powershell.exe -ExecutionPolicy Bypass -File "$TSUBAME_PS" $quiet 2>&1)
PS_EXIT=$?
set -e

# --- After ---
sleep 2
NEW_MAC=$(get_windows_mac)
NEW_SSID=$(get_windows_ssid)
NEW_BSSID=$(get_windows_bssid)

log "AFTER:  MAC=$NEW_MAC  SSID=$NEW_SSID (PS exit=$PS_EXIT)"

# --- Log to tsubame.db ---
if [ -f "$TSUBAME_DB" ]; then
    sqlite3 "$TSUBAME_DB" "
        INSERT INTO events (timestamp, event_type, ssid, net_type, mac_address, adapter_name, detail)
        VALUES (
            datetime('now', '+9 hours'),
            'mac_change',
            '$(echo "$OLD_SSID" | sed "s/'/''/g")',
            'wifi',
            '$(echo "$NEW_MAC" | sed "s/'/''/g")',
            'Wi-Fi',
            'spoof $(echo "$OLD_MAC" | sed "s/'/''/g") -> $(echo "$NEW_MAC" | sed "s/'/''/g") | exit=$PS_EXIT'
        );
    " 2>/dev/null || true

    sqlite3 "$TSUBAME_DB" "
        INSERT INTO sessions (connect_time, ssid, bssid, net_type, mac_address, adapter_name, rotate_count)
        VALUES (
            datetime('now', '+9 hours'),
            '$(echo "$NEW_SSID" | sed "s/'/''/g")',
            '$(echo "$NEW_BSSID" | sed "s/'/''/g")',
            'wifi',
            '$(echo "$NEW_MAC" | sed "s/'/''/g")',
            'Wi-Fi',
            1
        );
    " 2>/dev/null || true
fi

# --- Trigger tsubame scan ---
if [ -x "$TSUBAME_BIN" ]; then
    "$TSUBAME_BIN" --once >> "$TSUBAME_LOG" 2>&1 || true
fi

# --- Summary ---
case $PS_EXIT in
    0) log "OK:   $OLD_MAC -> $NEW_MAC ($NEW_SSID)" ;;
    2) log "WARN: MAC mismatch: expected $(echo "$PS_OUTPUT" | grep '^NEW:' | sed 's/^NEW: *//'), got $NEW_MAC" ;;
    3) log "WARN: Adapter status is not Up (still $NEW_SSID)" ;;
    *) log "FAIL: exit=$PS_EXIT" ;;
esac

exit $PS_EXIT
