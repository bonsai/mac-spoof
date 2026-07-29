#!/usr/bin/env bash
# install.sh — Install mac-spoof toolchain
#
# This script:
#   1. Creates ~/.wifi-mac-tracker directory
#   2. Initializes DB from schema.sql
#   3. Creates default meta.json if not present
#   4. Copies wifi-mac-rotate.sh + .ps1 to /usr/local/bin
#   5. Shows crontab instructions
#
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.wifi-mac-tracker}"
BIN_DIR="/usr/local/bin"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== mac-spoof installer ==="
echo ""

# Step 1: Create data directory
mkdir -p "$INSTALL_DIR"
echo "[1] Directory: $INSTALL_DIR"

# Step 2: Initialize DB
if [ ! -f "$INSTALL_DIR/tsubame.db" ]; then
    if [ -f "$REPO_DIR/schema.sql" ]; then
        sqlite3 "$INSTALL_DIR/tsubame.db" < "$REPO_DIR/schema.sql"
        echo "[2] DB created: $INSTALL_DIR/tsubame.db"
    else
        echo "[2] WARN: schema.sql not found, skipping DB init"
    fi
else
    echo "[2] DB already exists: $INSTALL_DIR/tsubame.db"
fi

# Step 3: Default meta file
if [ ! -f "$INSTALL_DIR/tsubame-meta.json" ]; then
    if [ -f "$REPO_DIR/config/meta.template.json" ]; then
        cp "$REPO_DIR/config/meta.template.json" "$INSTALL_DIR/tsubame-meta.json"
        echo "[3] Meta created: $INSTALL_DIR/tsubame-meta.json (edit as needed)"
    else
        echo "[3] WARN: template not found, skipping meta"
    fi
else
    echo "[3] Meta already exists: $INSTALL_DIR/tsubame-meta.json"
fi

# Step 4: Install scripts to /usr/local/bin
if [ -d "$BIN_DIR" ]; then
    cp "$REPO_DIR/wifi-mac-rotate.sh" "$BIN_DIR/wifi-mac-rotate"
    cp "$REPO_DIR/wifi-mac-rotate.ps1" "$BIN_DIR/wifi-mac-rotate.ps1"
    chmod +x "$BIN_DIR/wifi-mac-rotate"
    echo "[4] Installed: $BIN_DIR/wifi-mac-rotate"
    echo "               $BIN_DIR/wifi-mac-rotate.ps1"
else
    echo "[4] WARN: $BIN_DIR not writable, using repo dir directly"
    chmod +x "$REPO_DIR/wifi-mac-rotate.sh"
fi

echo ""
echo "=== Done ==="
echo ""
echo "Quick start:"
echo "  wifi-mac-rotate status          # Check current MAC/SSID"
echo "  wifi-mac-rotate                 # Rotate MAC now"
echo ""
echo "Cron (every 45 min):"
echo "  # True 45-min intervals:"
echo "  0,45  0,3,6,9,12,15,18,21  * * *  wifi-mac-rotate cron"
echo "  30    1,4,7,10,13,16,19,22 * * *  wifi-mac-rotate cron"
echo "  15    2,5,8,11,14,17,20,23 * * *  wifi-mac-rotate cron"
echo ""
echo "Env:"
echo "  TSUBAME_DB=$INSTALL_DIR/tsubame.db"
echo "  TSUBAME_META=$INSTALL_DIR/tsubame-meta.json"
echo ""
echo "Note: PowerShell script requires admin privileges."
echo "Run Windows Terminal as Admin for first setup."
