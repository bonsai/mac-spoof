#!/usr/bin/env bash
# wifi-mac-rotate.sh — WSL wrapper: MAC spoof + DB logging
#
# Usage:
#   ./wifi-mac-rotate.sh              Rotate MAC + log to DB
#   ./wifi-mac-rotate.sh status       Show current MAC/SSID
#   ./wifi-mac-rotate.sh cron         Quiet mode (for cron)
#
# Dependencies:
#   - powershell.exe (Windows, admin)
#   - sqlite3 (WSL)
#
# Environment:
#   MAC_SPOOF_DB     Path to mac-spoof.db (default: ~/.wifi-mac-tracker/mac-spoof.db)
#   MAC_SPOOF_META   Path to meta.json   (default: ~/.wifi-mac-tracker/meta.json)
#   MAC_SPOOF_PS     Path to wifi-mac-rotate.ps1 (default: same dir as this script)

set -euo pipefail

: "${MAC_SPOOF_DB:=$HOME/.wifi-mac-tracker/mac-spoof.db}"
: "${MAC_SPOOF_META:=$HOME/.wifi-mac-tracker/meta.json}"
: "${MAC_SPOOF_PS:=$(cd "$(dirname "$0")" && pwd)/wifi-mac-rotate.ps1}"
: "${MAC_SPOOF_LOG:=$HOME/.wifi-mac-tracker/rotate.log}"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$MAC_SPOOF_LOG"
    echo "$msg"
}

get_mac()  { powershell.exe -Command "Get-NetAdapter -Name 'Wi-Fi' | Select-Object -ExpandProperty MacAddress" 2>/dev/null | tr -d '\r\n'; }
get_ssid() { powershell.exe -Command "netsh wlan show interfaces | findstr 'SSID'" 2>/dev/null | head -1 | sed 's/.*SSID\s*:\s*//' | tr -d '\r\n'; }
get_bssid(){ powershell.exe -Command "netsh wlan show interfaces | findstr 'BSSID'" 2>/dev/null | head -1 | sed 's/.*BSSID\s*:\s*//' | tr -d '\r\n' | sed 's/^ *//'; }

case "${1:-}" in
    status)
        echo "MAC=$(get_mac)  SSID=$(get_ssid)"
        exit 0
        ;;
    cron) quiet="-Quiet" ;;
esac
quiet="${quiet:-}"

OLD_MAC=$(get_mac)
OLD_SSID=$(get_ssid)
OLD_BSSID=$(get_bssid)
log "BEFORE: MAC=$OLD_MAC  SSID=$OLD_SSID"

set +e
PS_OUT=$(powershell.exe -ExecutionPolicy Bypass -File "$MAC_SPOOF_PS" $quiet 2>&1)
PS_EXIT=$?
set -e

sleep 2
NEW_MAC=$(get_mac)
NEW_SSID=$(get_ssid)
NEW_BSSID=$(get_bssid)
log "AFTER:  MAC=$NEW_MAC  SSID=$NEW_SSID (exit=$PS_EXIT)"

if [ -f "$MAC_SPOOF_DB" ]; then
    sqlite3 "$MAC_SPOOF_DB" "
        INSERT INTO events (timestamp, event_type, ssid, net_type, mac_address, detail)
        VALUES (datetime('now','+9 hours'), 'mac_change', '$(echo "$OLD_SSID"|sed "s/'/''/g")', 'wifi',
                '$(echo "$NEW_MAC"|sed "s/'/''/g")',
                'spoof $(echo "$OLD_MAC"|sed "s/'/''/g") -> $(echo "$NEW_MAC"|sed "s/'/''/g") | exit=$PS_EXIT');
        INSERT INTO sessions (connect_time, ssid, bssid, net_type, mac_address, rotate_count)
        VALUES (datetime('now','+9 hours'), '$(echo "$NEW_SSID"|sed "s/'/''/g")',
                '$(echo "$NEW_BSSID"|sed "s/'/''/g")', 'wifi',
                '$(echo "$NEW_MAC"|sed "s/'/''/g")', 1);
    " 2>/dev/null || true
fi

# Run ms scan if available
if command -v ms &>/dev/null; then
    ms scan >> "$MAC_SPOOF_LOG" 2>&1 || true
fi

case $PS_EXIT in
    0) log "OK:   $OLD_MAC -> $NEW_MAC ($NEW_SSID)" ;;
    2) log "WARN: MAC mismatch" ;;
    3) log "WARN: adapter not Up" ;;
    *) log "FAIL: exit=$PS_EXIT" ;;
esac

exit $PS_EXIT
