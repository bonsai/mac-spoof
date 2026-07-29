package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"
	"time"
)

const version = "1.0.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(0)
	}

	cmd := os.Args[1]

	switch cmd {
	case "detect":
		runDetect()
	case "speed":
		runSpeed()
	case "scan":
		runScan()
	case "status":
		runStatus()
	case "probes":
		runProbes()
	case "sessions":
		runSessions()
	case "networks":
		runNetworks()
	case "version", "--version", "-v":
		fmt.Println("mac-spoof version", version)
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", cmd)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Println(`mac-spoof — WiFi MAC spoofing status tool

Usage:
  ms detect       Live WiFi info (no DB)
  ms speed        Speed test only
  ms scan         Detect + speed + record to DB
  ms status       Show status from DB
  ms probes       Probe history
  ms sessions     Session history
  ms networks     Known networks
  ms version      Show version

Environment:
  MAC_SPOOF_DB     DB path     (default: ~/.wifi-mac-tracker/mac-spoof.db)
  MAC_SPOOF_META   Meta path   (default: ~/.wifi-mac-tracker/meta.json)
`)
}

// ---------------------------------------------------------------------------
// detect
// ---------------------------------------------------------------------------

func runDetect() {
	w, err := detectWiFi()
	if err != nil {
		fmt.Fprintf(os.Stderr, "detect failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("=== live detect ===")
	b, _ := json.MarshalIndent(w, "", "  ")
	fmt.Println(string(b))
}

// ---------------------------------------------------------------------------
// speed
// ---------------------------------------------------------------------------

func runSpeed() {
	fmt.Print("speed test... ")
	r := speedTest()
	fmt.Println()
	if r.Error != "" {
		fmt.Printf("  error: %s\n", r.Error)
		os.Exit(1)
	}
	fmt.Printf("  download: %.2f Mbps\n", r.DownMbps)
	fmt.Printf("  latency:  %.0f ms\n", r.LatencyMs)
}

// ---------------------------------------------------------------------------
// scan
// ---------------------------------------------------------------------------

func runScan() {
	dbPath := defaultDBPath()
	db, err := openDB(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "DB init failed: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	// Load meta
	meta := loadMeta()

	// Detect WiFi
	fmt.Println("detecting...")
	w, err := detectWiFi()
	if err != nil {
		fmt.Fprintf(os.Stderr, "detect failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("  SSID:    %s\n", w.SSID)
	fmt.Printf("  MAC:     %s\n", w.MAC)
	fmt.Printf("  signal:  %d%%\n", w.Signal)
	fmt.Printf("  IP:      %s\n", w.IP)

	// Speed test
	fmt.Print("speed test... ")
	s := speedTest()
	if s.Error != "" {
		fmt.Printf("  (%s)\n", s.Error)
	} else {
		fmt.Printf("  %.2f Mbps, %.0f ms\n", s.DownMbps, s.LatencyMs)
	}

	// Determine net_type
	netType := "wifi"
	ssidUpper := strings.ToUpper(w.SSID)
	if strings.Contains(ssidUpper, "MCD") || strings.Contains(ssidUpper, "MCDONALD") {
		netType = "wifi"
	}

	ts := nowJST()

	// Insert probe
	probe := &Probe{
		Timestamp: ts,
		NetType:   netType,
		SSID:      w.SSID,
		BSSID:     w.BSSID,
		MAC:       w.MAC,
		IP:        w.IP,
		Signal:    w.Signal,
		DownMbps:  s.DownMbps,
		LatencyMs: s.LatencyMs,
		Location:  meta["location"],
		Building:  meta["building"],
		Floor:     meta["floor"],
		Note:      fmt.Sprintf("rx=%d tx=%d ch=%d", w.RxRate, w.TxRate, w.Channel),
	}
	if err := insertProbe(db, probe); err != nil {
		fmt.Fprintf(os.Stderr, "insert probe failed: %v\n", err)
	}

	// Insert event
	if err := insertEvent(db, &Event{
		Timestamp: ts,
		Type:      "probe",
		SSID:      w.SSID,
		MAC:       w.MAC,
		Detail:    fmt.Sprintf("down=%.1f sig=%d%%", s.DownMbps, w.Signal),
	}); err != nil {
		fmt.Fprintf(os.Stderr, "insert event failed: %v\n", err)
	}

	// Upsert network
	if w.SSID != "" {
		if err := upsertNetwork(db, &Network{
			SSID:   w.SSID,
			BSSID:  w.BSSID,
			NetType: netType,
		}, ts); err != nil {
			fmt.Fprintf(os.Stderr, "upsert network failed: %v\n", err)
		}
	}

	fmt.Printf("\n  ✓ recorded to %s\n", dbPath)
}

// ---------------------------------------------------------------------------
// status
// ---------------------------------------------------------------------------

func runStatus() {
	dbPath := defaultDBPath()
	if !fileExists(dbPath) {
		fmt.Println("No DB yet. Run 'ms scan' first.")
		return
	}

	db, err := openDB(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "DB open failed: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	probe, err := latestProbe(db)
	if err != nil {
		fmt.Println("No probe data. Run 'ms scan' first.")
		return
	}

	meta := loadMeta()

	fmt.Println("=== status ===")
	fmt.Printf("  last probe:  %s\n", probe.Timestamp)
	fmt.Printf("  type:        %s\n", probe.NetType)
	fmt.Printf("  SSID:        %s\n", orNA(probe.SSID))
	fmt.Printf("  BSSID:       %s\n", orNA(probe.BSSID))
	fmt.Printf("  MAC:         %s\n", orNA(probe.MAC))
	fmt.Printf("  IP:          %s\n", orNA(probe.IP))
	fmt.Printf("  signal:      %d%%\n", probe.Signal)
	fmt.Printf("  download:    %s\n", fmtMbps(probe.DownMbps))
	fmt.Printf("  latency:     %s\n", fmtMs(probe.LatencyMs))

	if probe.Location != "" {
		fmt.Printf("  location:    %s\n", probe.Location)
	}
	if probe.Building != "" {
		fmt.Printf("  building:    %s\n", probe.Building)
	}

	if len(meta) > 0 {
		fmt.Println()
		fmt.Println("=== metadata ===")
		for k, v := range meta {
			fmt.Printf("  %s: %s\n", k, v)
		}
	}

	events, _ := recentEvents(db, 5)
	if len(events) > 0 {
		fmt.Println()
		fmt.Println("=== recent events ===")
		for _, e := range events {
			detail := e.Detail
			if len(detail) > 60 {
				detail = detail[:60] + "..."
			}
			fmt.Printf("  %s  %-12s  %s\n", e.Timestamp, e.Type, detail)
		}
	}
}

// ---------------------------------------------------------------------------
// probes
// ---------------------------------------------------------------------------

func runProbes() {
	dbPath := defaultDBPath()
	if !fileExists(dbPath) {
		fmt.Println("No DB yet.")
		return
	}

	db, err := openDB(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "DB open failed: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	probes, err := recentProbes(db, 20)
	if err != nil || len(probes) == 0 {
		fmt.Println("No probe data.")
		return
	}

	fmt.Printf("=== probes (last %d) ===\n", len(probes))
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
	fmt.Fprintln(w, "  time\ttype\tdownload\tsignal\tmac\tlocation")
	for _, p := range probes {
		t := shortenTime(p.Timestamp)
		fmt.Fprintf(w, "  %s\t%s\t%s\t%d%%\t%s\t%s\n",
			t, p.NetType, fmtMbps(p.DownMbps), p.Signal, truncMAC(p.MAC), p.Location)
	}
	w.Flush()
}

// ---------------------------------------------------------------------------
// sessions
// ---------------------------------------------------------------------------

func runSessions() {
	dbPath := defaultDBPath()
	if !fileExists(dbPath) {
		fmt.Println("No DB yet.")
		return
	}

	db, err := openDB(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "DB open failed: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	rows, err := db.Query("SELECT connect_time, ssid, mac_address, rotate_count FROM sessions ORDER BY connect_time DESC LIMIT 20")
	if err != nil {
		fmt.Println("No session data.")
		return
	}
	defer rows.Close()

	var sessions []Session
	for rows.Next() {
		var s Session
		if err := rows.Scan(&s.ConnectTime, &s.SSID, &s.MAC, &s.RotateCount); err != nil {
			continue
		}
		sessions = append(sessions, s)
	}

	if len(sessions) == 0 {
		fmt.Println("No session data.")
		return
	}

	fmt.Printf("=== sessions (last %d) ===\n", len(sessions))
	for _, s := range sessions {
		fmt.Printf("  %s  %-20s  %s  rotate=%d\n",
			s.ConnectTime, s.SSID, truncMAC(s.MAC), s.RotateCount)
	}
}

// ---------------------------------------------------------------------------
// networks
// ---------------------------------------------------------------------------

func runNetworks() {
	dbPath := defaultDBPath()
	if !fileExists(dbPath) {
		fmt.Println("No DB yet.")
		return
	}

	db, err := openDB(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "DB open failed: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	nets, err := allNetworks(db)
	if err != nil || len(nets) == 0 {
		fmt.Println("No networks recorded.")
		return
	}

	fmt.Printf("=== known networks (%d) ===\n", len(nets))
	for _, n := range nets {
		rot := " "
		if n.MacRotated {
			rot = "R"
		}
		ban := " "
		if n.Banned {
			ban = "X"
		}
		fmt.Printf("  [%s%s] %-20s  %-20s  %-10s  %dsessions\n", rot, ban,
			n.SSID, n.BSSID, n.NetType, n.SessionCount)
		if n.Notes != "" {
			fmt.Printf("       %s\n", n.Notes)
		}
	}
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

func loadMeta() map[string]string {
	path := defaultMetaPath()
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var m map[string]string
	if err := json.Unmarshal(data, &m); err != nil {
		return nil
	}
	return m
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func orNA(s string) string {
	if s == "" {
		return "N/A"
	}
	return s
}

func fmtMbps(v float64) string {
	if v == 0 {
		return "N/A"
	}
	return fmt.Sprintf("%.1f Mbps", v)
}

func fmtMs(v float64) string {
	if v == 0 {
		return "N/A"
	}
	return fmt.Sprintf("%.0f ms", v)
}

func shortenTime(ts string) string {
	t, err := time.Parse("2006-01-02T15:04:05-07:00", ts)
	if err != nil {
		if len(ts) > 16 {
			return ts[5:16]
		}
		return ts
	}
	return t.Format("01-02 15:04")
}

func truncMAC(mac string) string {
	if len(mac) > 17 {
		return mac[:17]
	}
	return mac
}
