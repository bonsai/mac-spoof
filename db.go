package main

import (
	"database/sql"
	"embed"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

//go:embed schema.sql
var schemaFS embed.FS

// Probe represents a single network probe record.
type Probe struct {
	Timestamp string  `json:"timestamp"`
	NetType   string  `json:"net_type"`
	SSID      string  `json:"ssid"`
	BSSID     string  `json:"bssid"`
	MAC       string  `json:"mac"`
	IP        string  `json:"ip"`
	Signal    int     `json:"signal"`
	DownMbps  float64 `json:"down_mbps"`
	LatencyMs float64 `json:"latency_ms"`
	Location  string  `json:"location"`
	Building  string  `json:"building"`
	Floor     string  `json:"floor"`
	Note      string  `json:"note"`
}

// Event represents a system event.
type Event struct {
	Timestamp string `json:"timestamp"`
	Type      string `json:"event_type"`
	SSID      string `json:"ssid"`
	MAC       string `json:"mac_address"`
	Detail    string `json:"detail"`
}

// Network represents a known Wi-Fi network.
type Network struct {
	SSID         string `json:"ssid"`
	BSSID        string `json:"bssid"`
	NetType      string `json:"net_type"`
	FirstSeen    string `json:"first_seen"`
	LastSeen     string `json:"last_seen"`
	SessionCount int    `json:"session_count"`
	MacRotated   bool   `json:"mac_rotated"`
	Banned       bool   `json:"banned"`
	Notes        string `json:"notes"`
}

// Session represents a connection session.
type Session struct {
	ConnectTime string `json:"connect_time"`
	SSID        string `json:"ssid"`
	MAC         string `json:"mac_address"`
	RotateCount int    `json:"rotate_count"`
}

func defaultDBPath() string {
	env := os.Getenv("MAC_SPOOF_DB")
	if env != "" {
		return env
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".wifi-mac-tracker", "mac-spoof.db")
}

func defaultMetaPath() string {
	env := os.Getenv("MAC_SPOOF_META")
	if env != "" {
		return env
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".wifi-mac-tracker", "meta.json")
}

func openDB(path string) (*sql.DB, error) {
	// Ensure directory exists
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("mkdir: %w", err)
	}

	db, err := sql.Open("sqlite3", path+"?_journal_mode=WAL&_busy_timeout=5000")
	if err != nil {
		return nil, fmt.Errorf("open: %w", err)
	}

	// Init schema
	schema, err := schemaFS.ReadFile("schema.sql")
	if err != nil {
		// fallback inline schema
		schema = []byte(inlineSchema)
	}
	if _, err := db.Exec(string(schema)); err != nil {
		db.Close()
		return nil, fmt.Errorf("schema: %w", err)
	}

	return db, nil
}

const inlineSchema = `
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
`

// ---------------------------------------------------------------------------
// CRUD
// ---------------------------------------------------------------------------

func insertProbe(db *sql.DB, p *Probe) error {
	_, err := db.Exec(`
		INSERT INTO probes (timestamp, net_type, ssid, bssid, mac, ip,
		                    signal, down_mbps, latency_ms,
		                    location, building, floor, note)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		p.Timestamp, p.NetType, p.SSID, p.BSSID, p.MAC, p.IP,
		p.Signal, p.DownMbps, p.LatencyMs,
		p.Location, p.Building, p.Floor, p.Note)
	return err
}

func insertEvent(db *sql.DB, e *Event) error {
	_, err := db.Exec(`
		INSERT INTO events (timestamp, event_type, ssid, mac_address, detail)
		VALUES (?, ?, ?, ?, ?)`,
		e.Timestamp, e.Type, e.SSID, e.MAC, e.Detail)
	return err
}

func upsertNetwork(db *sql.DB, n *Network, now string) error {
	// Check by BSSID
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM networks WHERE bssid = ?", n.BSSID).Scan(&count)
	if err != nil {
		return err
	}

	if count > 0 {
		_, err = db.Exec("UPDATE networks SET last_seen = ?, session_count = session_count + 1 WHERE bssid = ?", now, n.BSSID)
	} else {
		_, err = db.Exec(`
			INSERT INTO networks (ssid, bssid, net_type, first_seen, last_seen, mac_rotated)
			VALUES (?, ?, ?, ?, ?, 0)`, n.SSID, n.BSSID, n.NetType, now, now)
	}
	return err
}

func latestProbe(db *sql.DB) (*Probe, error) {
	row := db.QueryRow("SELECT * FROM probes ORDER BY timestamp DESC LIMIT 1")
	p := &Probe{}
	err := row.Scan(
		&[]interface{}{nil}[0], // id (skip)
		&p.Timestamp, &p.NetType, &p.SSID, &p.BSSID, &p.MAC, &p.IP,
		&p.Signal, &p.DownMbps, &p.LatencyMs,
		&p.Location, &p.Building, &p.Floor, &p.Note,
	)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func recentProbes(db *sql.DB, limit int) ([]Probe, error) {
	rows, err := db.Query("SELECT * FROM probes ORDER BY timestamp DESC LIMIT ?", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var probes []Probe
	for rows.Next() {
		var p Probe
		var id int
		if err := rows.Scan(
			&id, &p.Timestamp, &p.NetType, &p.SSID, &p.BSSID,
			&p.MAC, &p.IP, &p.Signal, &p.DownMbps, &p.LatencyMs,
			&p.Location, &p.Building, &p.Floor, &p.Note,
		); err != nil {
			return nil, err
		}
		probes = append(probes, p)
	}
	return probes, nil
}

func recentEvents(db *sql.DB, limit int) ([]Event, error) {
	rows, err := db.Query("SELECT timestamp, event_type, ssid, mac_address, detail FROM events ORDER BY timestamp DESC LIMIT ?", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.Timestamp, &e.Type, &e.SSID, &e.MAC, &e.Detail); err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	return events, nil
}

func allNetworks(db *sql.DB) ([]Network, error) {
	rows, err := db.Query("SELECT ssid, bssid, net_type, first_seen, last_seen, session_count, mac_rotated, banned, notes FROM networks ORDER BY last_seen DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var nets []Network
	for rows.Next() {
		var n Network
		if err := rows.Scan(&n.SSID, &n.BSSID, &n.NetType, &n.FirstSeen, &n.LastSeen,
			&n.SessionCount, &n.MacRotated, &n.Banned, &n.Notes); err != nil {
			return nil, err
		}
		nets = append(nets, n)
	}
	return nets, nil
}

func nowJST() string {
	loc := time.FixedZone("JST", 9*60*60)
	return time.Now().In(loc).Format("2006-01-02T15:04:05-07:00")
}
