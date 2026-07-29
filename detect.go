package main

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

// WiFiInfo holds the parsed result of a Wi-Fi interface scan.
type WiFiInfo struct {
	SSID    string `json:"ssid"`
	BSSID   string `json:"bssid"`
	MAC     string `json:"mac"`
	IP      string `json:"ip"`
	Signal  int    `json:"signal"`
	RSSI    int    `json:"rssi"`
	State   string `json:"state"`
	RxRate  int    `json:"rx_rate"`
	TxRate  int    `json:"tx_rate"`
	Channel int    `json:"channel"`
	Band    string `json:"band"`
}

func detectWiFi() (*WiFiInfo, error) {
	w := &WiFiInfo{}

	cmd := exec.Command("powershell.exe", "-Command", "netsh wlan show interfaces")
	out, err := cmd.Output()
	if err != nil {
		return w, fmt.Errorf("powershell/netsh failed: %w", err)
	}
	output := string(out)

	parsers := []struct {
		re  *regexp.Regexp
		fn  func(string)
	}{
		{regexp.MustCompile(`SSID\s*:\s*(.+)`), func(v string) { w.SSID = strings.TrimSpace(v) }},
		{regexp.MustCompile(`AP BSSID\s*:\s*(.+)`), func(v string) { w.BSSID = strings.TrimSpace(v) }},
		{regexp.MustCompile(`Physical address\s*:\s*(.+)`), func(v string) { w.MAC = strings.ToLower(strings.ReplaceAll(strings.TrimSpace(v), "-", ":")) }},
		{regexp.MustCompile(`Signal\s*:\s*(\d+)%`), func(v string) { w.Signal = parseInt(v) }},
		{regexp.MustCompile(`RSSI\s*:\s*(-?\d+)`), func(v string) { w.RSSI = parseInt(v) }},
		{regexp.MustCompile(`State\s*:\s*(.+)`), func(v string) { w.State = strings.TrimSpace(v) }},
		{regexp.MustCompile(`Receive rate \(Mbps\)\s*:\s*(\d+)`), func(v string) { w.RxRate = parseInt(v) }},
		{regexp.MustCompile(`Transmit rate \(Mbps\)\s*:\s*(\d+)`), func(v string) { w.TxRate = parseInt(v) }},
		{regexp.MustCompile(`Channel\s*:\s*(\d+)`), func(v string) { w.Channel = parseInt(v) }},
		{regexp.MustCompile(`Band\s*:\s*(.+)`), func(v string) { w.Band = strings.TrimSpace(v) }},
	}

	for _, p := range parsers {
		if m := p.re.FindStringSubmatch(output); len(m) > 1 {
			p.fn(m[1])
		}
	}

	// Get IP
	ipCmd := exec.Command("powershell.exe", "-Command",
		"Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi' | Select-Object -ExpandProperty IPAddress")
	if ipOut, err := ipCmd.Output(); err == nil {
		if ip := strings.TrimSpace(string(ipOut)); ip != "" {
			w.IP = ip
		}
	}

	return w, nil
}

func (w *WiFiInfo) String() string {
	b, _ := json.MarshalIndent(w, "", "  ")
	return string(b)
}

func parseInt(s string) int {
	n := 0
	for _, c := range s {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		} else if n > 0 {
			break
		}
	}
	return n
}
