package main

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

const speedTestURL = "https://proof.ovh.net/files/10Mb.dat"

// SpeedResult holds speed test measurements.
type SpeedResult struct {
	DownMbps  float64 `json:"down_mbps"`
	LatencyMs float64 `json:"latency_ms"`
	Error     string  `json:"error,omitempty"`
}

func speedTest() *SpeedResult {
	r := &SpeedResult{}

	// Measure latency via HEAD request
	start := time.Now()
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Head(speedTestURL)
	if err == nil {
		resp.Body.Close()
		r.LatencyMs = float64(time.Since(start).Milliseconds())
	}

	// Download test
	start = time.Now()
	req, err := http.NewRequest("GET", speedTestURL, nil)
	if err != nil {
		r.Error = fmt.Sprintf("request err: %v", err)
		return r
	}
	req.Header.Set("User-Agent", "mac-spoof/1.0")

	dlClient := &http.Client{Timeout: 30 * time.Second}
	resp, err = dlClient.Do(req)
	if err != nil {
		r.Error = fmt.Sprintf("download err: %v", err)
		return r
	}
	defer resp.Body.Close()

	n, err := io.Copy(io.Discard, resp.Body)
	if err != nil {
		r.Error = fmt.Sprintf("read err: %v", err)
		return r
	}

	elapsed := time.Since(start).Seconds()
	if elapsed > 0 {
		r.DownMbps = float64(n) * 8 / (1024 * 1024) / elapsed
		r.DownMbps = float64(int(r.DownMbps*100)) / 100 // round to 2dp
	}

	return r
}
