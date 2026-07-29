-- mac-spoof schema
-- Auto-created on first run if not exists

CREATE TABLE IF NOT EXISTS probes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   TEXT NOT NULL,
    net_type    TEXT NOT NULL,
    ssid        TEXT,
    bssid       TEXT,
    mac         TEXT,
    ip          TEXT,
    signal      INTEGER,
    down_mbps   REAL,
    latency_ms  REAL,
    location    TEXT,
    building    TEXT,
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
    ip_address      TEXT,
    speed_down_mbps REAL,
    signal_percent  INTEGER,
    rotate_count    INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS events (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp    TEXT NOT NULL,
    event_type   TEXT NOT NULL,
    ssid         TEXT,
    net_type     TEXT,
    mac_address  TEXT,
    detail       TEXT
);

CREATE TABLE IF NOT EXISTS networks (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    ssid           TEXT NOT NULL,
    bssid          TEXT,
    net_type       TEXT NOT NULL DEFAULT 'wifi',
    first_seen     TEXT NOT NULL,
    last_seen      TEXT NOT NULL,
    session_count  INTEGER DEFAULT 1,
    mac_rotated    INTEGER DEFAULT 0,
    banned         INTEGER DEFAULT 0,
    notes          TEXT
);
