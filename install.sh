#!/usr/bin/env bash
# install.sh — Build and install mac-spoof toolchain
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"

echo "=== mac-spoof installer ==="

# 1. Build Go binary
echo "[1] Building ms..."
cd "$REPO"
if command -v go &>/dev/null; then
    CGO_ENABLED=1 go build -o ms .
    echo "     -> $REPO/ms ($(du -h ms | cut -f1))"
else
    echo "     SKIP: Go not found"
fi

# 2. Install ms to PATH
if [ -f "$REPO/ms" ]; then
    mkdir -p ~/.local/bin
    cp "$REPO/ms" ~/.local/bin/ms
    echo "[2] Installed: ~/.local/bin/ms"
fi

# 3. Ensure data dir
DATA_DIR="${MAC_SPOOF_DATA_DIR:-$HOME/.wifi-mac-tracker}"
mkdir -p "$DATA_DIR"
echo "[3] Data dir: $DATA_DIR"

# 4. Init DB from schema
if [ ! -f "$DATA_DIR/mac-spoof.db" ] && [ -f "$REPO/schema.sql" ]; then
    sqlite3 "$DATA_DIR/mac-spoof.db" < "$REPO/schema.sql"
    echo "[4] DB created: $DATA_DIR/mac-spoof.db"
else
    echo "[4] DB already exists: $DATA_DIR/mac-spoof.db"
fi

# 5. Default meta file
META_PATH="${MAC_SPOOF_META:-$HOME/.wifi-mac-tracker/meta.json}"
if [ ! -f "$META_PATH" ]; then
    echo '{"location":"","building":"","floor":""}' > "$META_PATH"
    echo "[5] Meta created: $META_PATH"
else
    echo "[5] Meta exists: $META_PATH"
fi

echo ""
echo "=== Done ==="
echo ""
echo "Commands:"
echo "  ms detect        Live WiFi info"
echo "  ms speed         Speed test"
echo "  ms scan          Detect + speed -> DB"
echo "  ms status        Status from DB"
echo "  ms probes        Probe history"
echo "  ms sessions      Session history"
echo "  ms networks      Known networks"
echo ""
echo "Task tray (Windows PowerShell Admin):"
echo "  powershell -ExecutionPolicy Bypass -File $REPO/tray.ps1"
echo ""
echo "Cron (45min intervals):"
echo "  0,45 0,3,6,9,12,15,18,21 * * * $REPO/wifi-mac-rotate.sh cron"
echo "  30    1,4,7,10,13,16,19,22   * * * $REPO/wifi-mac-rotate.sh cron"
echo "  15    2,5,8,11,14,17,20,23   * * * $REPO/wifi-mac-rotate.sh cron"
echo ""
echo "Env:"
echo "  MAC_SPOOF_DB=$DATA_DIR/mac-spoof.db"
echo "  MAC_SPOOF_META=$META_PATH"
