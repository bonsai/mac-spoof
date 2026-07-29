-- database schema
-- Used by: tsubame-agent (Go), ms.py (Python CLI), wifi-mac-rotate.sh

CREATE TABLE IF NOT EXISTS tsubame_probes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   TEXT NOT NULL,
    net_type    TEXT NOT NULL,          -- wifi | ethernet | tethering | disconnected
    ssid        TEXT,
    bssid       TEXT,
    mac         TEXT,
    ip          TEXT,
    signal      INTEGER,
    down_mbps   REAL,
    up_mbps     REAL,
    latency_ms  REAL,
    isp         TEXT,
    lat         REAL,
    lon         REAL,
    server      TEXT,
    bytes_recv  INTEGER,
    duration_sec REAL,
    location    TEXT,
    building    TEXT,
    indoor      TEXT,
    floor       TEXT,
    note        TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    connect_time    TEXT NOT NULL,
    disconnect_time TEXT,
    ssid            TEXT,
    bssid           TEXT,
    net_type        TEXT NOT NULL DEFAULT 'wifi',
    mac_address     TEXT,
    adapter_name    TEXT DEFAULT 'Wi-Fi',
    ip_address      TEXT,
    speed_down_mbps REAL,
    speed_up_mbps   REAL,
    latency_ms      REAL,
    signal_percent  INTEGER,
    duration_sec    INTEGER,
    rotate_count    INTEGER DEFAULT 0,
    disconnected_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_sessions_ssid ON sessions(ssid);
CREATE INDEX IF NOT EXISTS idx_sessions_net_type ON sessions(net_type);

CREATE TABLE IF NOT EXISTS events (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp    TEXT NOT NULL,
    event_type   TEXT NOT NULL,    -- mac_change | connect | disconnect | probe
    ssid         TEXT,
    net_type     TEXT,
    mac_address  TEXT,
    adapter_name TEXT DEFAULT 'Wi-Fi',
    detail       TEXT
);

CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);

CREATE TABLE IF NOT EXISTS networks (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    ssid           TEXT NOT NULL,
    bssid          TEXT,
    net_type       TEXT NOT NULL DEFAULT 'wifi',
    security       TEXT,
    first_seen     TEXT NOT NULL,
    last_seen      TEXT NOT NULL,
    session_count  INTEGER DEFAULT 1,
    avg_speed_down REAL,
    avg_speed_up   REAL,
    mac_rotated    INTEGER DEFAULT 0,
    banned         INTEGER DEFAULT 0,
    ban_reason     TEXT,
    notes          TEXT
);

CREATE INDEX IF NOT EXISTS idx_networks_ssid ON networks(ssid);

CREATE TABLE IF NOT EXISTS strategies (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    net_type           TEXT NOT NULL,
    ssid_pattern       TEXT,
    rule_name          TEXT NOT NULL,
    rotate_interval_min INTEGER DEFAULT 30,
    pre_disconnect_sec  INTEGER DEFAULT 5,
    speed_threshold_mbps REAL DEFAULT 1.0,
    max_disconnect_sec   INTEGER DEFAULT 30,
    enabled            INTEGER DEFAULT 1,
    priority           INTEGER DEFAULT 0,
    notes              TEXT
);

CREATE TABLE IF NOT EXISTS decisions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   TEXT NOT NULL,
    session_id  INTEGER,
    action      TEXT NOT NULL,
    reason      TEXT,
    strategy_id INTEGER,
    executed    INTEGER DEFAULT 0
);

-- Default strategies
INSERT OR IGNORE INTO strategies (net_type, ssid_pattern, rule_name, rotate_interval_min, priority, notes) VALUES
    ('wifi',       'McDonald%',     'MCD WiFi - rotate every 45min', 45, 100, 'Bypass 1-hour time limit'),
    ('wifi',       '%',             'General WiFi - no rotate',      0,   50, 'Default: no auto rotation'),
    ('tethering',  '%',             'Tethering - no rotate needed',  0,   50, 'No MAC limit on tethering'),
    ('ethernet',   '%',             'Ethernet - no rotate',          0,   50, 'Wired: not applicable');
