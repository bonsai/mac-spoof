#!/usr/bin/env python3
"""tsubame — Wi-Fi session tracker for MAC-spoofing environments

Queries the local SQLite DB (tsubame.db) which records:
  - Network probes (5-min interval by tsubame-agent)
  - Session connect/disconnect events
  - MAC rotation history
  - Known networks

Commands:
  status          Show current connection status and recent events
  probes          Show recent probe results
  sessions        Show recent sessions
  networks        List known networks
  scan            Trigger an immediate probe

Environment:
  TSUBAME_DB      Path to tsubame.db (default: ~/.wifi-mac-tracker/tsubame.db)
  TSUBAME_META    Path to meta.json  (default: ~/.wifi-mac-tracker/tsubame-meta.json)
  TSUBAME_BIN     Path to tsubame-agent binary (default: ~/.local/bin/tsubame-agent)
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# --- Default paths ---
DEFAULT_DB = Path.home() / ".wifi-mac-tracker" / "tsubame.db"
DEFAULT_META = Path.home() / ".wifi-mac-tracker" / "tsubame-meta.json"
DEFAULT_BIN = Path.home() / ".local/bin" / "tsubame-agent"


def get_db_path() -> Path:
    env = os.environ.get("TSUBAME_DB")
    return Path(env) if env else DEFAULT_DB


def get_meta_path() -> Path:
    env = os.environ.get("TSUBAME_META")
    return Path(env) if env else DEFAULT_META


def get_bin_path() -> Path:
    env = os.environ.get("TSUBAME_BIN")
    return Path(env) if env else DEFAULT_BIN


def get_db() -> sqlite3.Connection:
    path = get_db_path()
    if not path.exists():
        print(f"[error] DB not found: {path}", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    return conn


def load_meta() -> dict:
    path = get_meta_path()
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return {}


def fmt_time(ts: str) -> str:
    if not ts:
        return "N/A"
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return ts


def fmt_speed(v: float | None) -> str:
    if v is None or v == 0:
        return "N/A"
    return f"{v:.1f} Mbps"


def cmd_status(args):
    conn = get_db()
    meta = load_meta()
    cur = conn.execute("SELECT * FROM tsubame_probes ORDER BY timestamp DESC LIMIT 1")
    row = cur.fetchone()

    if not row:
        print("No probe data yet")
        conn.close()
        return

    print("=== tsubame status ===")
    print(f"  last probe:  {fmt_time(row['timestamp'])}")
    print(f"  net type:    {row['net_type']}")
    print(f"  SSID:        {row['ssid'] or 'N/A'}")
    print(f"  BSSID:       {row['bssid'] or 'N/A'}")
    print(f"  MAC:         {row['mac']}")
    print(f"  IP:          {row['ip']}")
    print(f"  signal:      {row['signal']}%")
    print(f"  download:    {fmt_speed(row['down_mbps'])}")
    print(f"  upload:      {fmt_speed(row['up_mbps'])}")
    print(f"  latency:     {row['latency_ms'] or 'N/A'} ms")

    if row['location']:
        print(f"  location:    {row['location']}")
    if row['building']:
        print(f"  building:    {row['building']}")

    if meta:
        print()
        print("=== metadata ===")
        for k, v in meta.items():
            print(f"  {k}: {v}")

    cur = conn.execute("SELECT * FROM events ORDER BY timestamp DESC LIMIT 5")
    events = cur.fetchall()
    if events:
        print()
        print("=== recent events ===")
        for e in events:
            print(f"  {fmt_time(e['timestamp'])}  {e['event_type']:12}  {e['mac_address'] or ''}  {e['detail'] or ''}")

    conn.close()


def cmd_probes(args):
    conn = get_db()
    cur = conn.execute("SELECT * FROM tsubame_probes ORDER BY timestamp DESC LIMIT ?", (args.limit,))
    rows = cur.fetchall()
    if not rows:
        print("No probe data")
        conn.close()
        return

    print(f"=== probes (last {len(rows)}) ===")
    for r in rows:
        t = fmt_time(r['timestamp'])
        nt = r['net_type'] or '?'
        dn = fmt_speed(r['down_mbps'])
        up = fmt_speed(r['up_mbps'])
        loc = r['location'] or ''
        mac = (r['mac'] or '')[:17]
        print(f"  {t}  {nt:<10}  ↓{dn:>10}  ↑{up:>10}  {mac}  {loc}")

    conn.close()


def cmd_sessions(args):
    conn = get_db()
    cur = conn.execute("SELECT * FROM sessions ORDER BY connect_time DESC LIMIT ?", (args.limit,))
    rows = cur.fetchall()
    if not rows:
        print("No session data")
        conn.close()
        return

    print(f"=== sessions (last {len(rows)}) ===")
    for s in rows:
        ct = fmt_time(s['connect_time'])
        ssid = s['ssid'] or 'N/A'
        mac = (s['mac_address'] or '')[:17]
        rot = s['rotate_count'] or 0
        print(f"  {ct}  {ssid:<20}  {mac}  rotate={rot}")

    conn.close()


def cmd_networks(args):
    conn = get_db()
    cur = conn.execute("SELECT * FROM networks ORDER BY last_seen DESC")
    rows = cur.fetchall()
    if not rows:
        print("No networks recorded")
        conn.close()
        return

    print(f"=== known networks ({len(rows)}) ===")
    for n in rows:
        ssid = n['ssid'] or 'N/A'
        bssid = n['bssid'] or 'N/A'
        nt = n['net_type'] or '?'
        cnt = n['session_count'] or 0
        rot = "R" if n['mac_rotated'] else " "
        ban = "X" if n['banned'] else " "
        print(f"  [{rot}{ban}] {ssid:<20}  {bssid:<20}  {nt:<10}  {cnt}sessions")
        print(f"       first: {n['first_seen']}  last: {n['last_seen']}")

    conn.close()


def cmd_scan(args):
    path = get_bin_path()
    if not path.exists():
        print(f"[error] binary not found: {path}", file=sys.stderr)
        sys.exit(1)

    print("scanning...")
    try:
        r = subprocess.run([str(path), "--once"], capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            print("  done")
            if r.stdout.strip():
                print(f"  {r.stdout.strip()}")
        else:
            print(f"  [error] {r.stderr}")
    except subprocess.TimeoutExpired:
        print("  [error] timeout")
    except Exception as e:
        print(f"  [error] {e}")


def main():
    parser = argparse.ArgumentParser(description="tsubame — Wi-Fi session tracker")
    sub = parser.add_subparsers(dest="cmd")

    p_status = sub.add_parser("status", help="Show current status")
    p_status.set_defaults(func=cmd_status)

    p_probes = sub.add_parser("probes", help="Show recent probes")
    p_probes.add_argument("--limit", type=int, default=20)
    p_probes.set_defaults(func=cmd_probes)

    p_sessions = sub.add_parser("sessions", help="Show recent sessions")
    p_sessions.add_argument("--limit", type=int, default=20)
    p_sessions.set_defaults(func=cmd_sessions)

    p_networks = sub.add_parser("networks", help="List known networks")
    p_networks.set_defaults(func=cmd_networks)

    p_scan = sub.add_parser("scan", help="Trigger immediate scan")
    p_scan.set_defaults(func=cmd_scan)

    args = parser.parse_args()
    if not args.cmd:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
