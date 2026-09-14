package realtime

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHub_RegisterAndUnregister(t *testing.T) {
	hub := NewHubWithInterval(0) // disable heartbeat for registration test
	defer hub.Close()

	if count := hub.ClientCount(); count != 0 {
		t.Fatalf("expected 0 clients initially, got %d", count)
	}

	ch1 := make(chan []byte, 10)
	ch2 := make(chan []byte, 10)

	hub.Register(ch1)
	hub.Register(ch2)
	hub.Register(nil) // should be safely ignored

	if count := hub.ClientCount(); count != 2 {
		t.Fatalf("expected 2 clients after registration, got %d", count)
	}

	hub.Unregister(ch1)
	hub.Unregister(nil) // should be safely ignored

	if count := hub.ClientCount(); count != 1 {
		t.Fatalf("expected 1 client after unregistering ch1, got %d", count)
	}

	hub.Unregister(ch2)
	if count := hub.ClientCount(); count != 0 {
		t.Fatalf("expected 0 clients after unregistering all, got %d", count)
	}
}

func TestHub_BroadcastFormatting(t *testing.T) {
	hub := NewHubWithInterval(0)
	defer hub.Close()

	ch := make(chan []byte, 10)
	hub.Register(ch)

	// Test typed broadcast with struct
	payload := map[string]interface{}{
		"sale_id":     "s-100",
		"total_cents": 50000,
	}

	if err := hub.Broadcast("sale.created", payload); err != nil {
		t.Fatalf("unexpected broadcast error: %v", err)
	}

	select {
	case msg := <-ch:
		expectedPrefix := "event: sale.created\ndata: "
		if !strings.HasPrefix(string(msg), expectedPrefix) {
			t.Fatalf("expected message to start with %q, got %q", expectedPrefix, string(msg))
		}
		if !strings.HasSuffix(string(msg), "\n\n") {
			t.Fatalf("expected message to end with double newline, got %q", string(msg))
		}
		var parsed map[string]interface{}
		dataLine := strings.TrimPrefix(string(msg), expectedPrefix)
		dataLine = strings.TrimSuffix(dataLine, "\n\n")
		if err := json.Unmarshal([]byte(dataLine), &parsed); err != nil {
			t.Fatalf("failed to unmarshal broadcasted JSON data: %v", err)
		}
		if parsed["sale_id"] != "s-100" || parsed["total_cents"] != float64(50000) {
			t.Errorf("unexpected parsed payload: %+v", parsed)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("timed out waiting for broadcast message")
	}

	// Test broadcast with empty event type (raw data frame)
	if err := hub.Broadcast("", `{"raw":true}`); err != nil {
		t.Fatalf("unexpected broadcast error: %v", err)
	}

	select {
	case msg := <-ch:
		expected := "data: {\"raw\":true}\n\n"
		if string(msg) != expected {
			t.Fatalf("expected %q, got %q", expected, string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("timed out waiting for raw broadcast message")
	}

	// Test unmarshalable data returns error
	unmarshalable := make(chan int)
	if err := hub.Broadcast("error.test", unmarshalable); err == nil {
		t.Fatal("expected error broadcasting unmarshalable data, got nil")
	}
}

func TestHub_BroadcastSale(t *testing.T) {
	hub := NewHubWithInterval(0)
	defer hub.Close()

	ch := make(chan []byte, 5)
	hub.Register(ch)

	sale := map[string]interface{}{
		"sale_id": "sale-xyz",
	}

	if err := hub.BroadcastSale(sale); err != nil {
		t.Fatalf("unexpected error from BroadcastSale: %v", err)
	}

	select {
	case msg := <-ch:
		if !strings.HasPrefix(string(msg), "event: sale.created\n") {
			t.Fatalf("expected event: sale.created, got %s", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("timeout waiting for BroadcastSale message")
	}
}

func TestHub_SlowClientNonBlocking(t *testing.T) {
	hub := NewHubWithInterval(0)
	defer hub.Close()

	// Register an unbuffered channel with no reader to simulate a stuck/slow client
	slowCh := make(chan []byte)
	hub.Register(slowCh)

	done := make(chan struct{})
	go func() {
		_ = hub.Broadcast("test", map[string]string{"foo": "bar"})
		close(done)
	}()

	select {
	case <-done:
		// Broadcast completed without deadlocking
	case <-time.After(200 * time.Millisecond):
		t.Fatal("hub.Broadcast blocked on unbuffered slow client")
	}
}

func TestHub_Heartbeat(t *testing.T) {
	// Heartbeat ticker running at 20ms
	hub := NewHubWithInterval(20 * time.Millisecond)
	defer hub.Close()

	ch := make(chan []byte, 10)
	hub.Register(ch)

	select {
	case msg := <-ch:
		if string(msg) != ": ping\n\n" {
			t.Fatalf("expected heartbeat ': ping\\n\\n', got %q", string(msg))
		}
	case <-time.After(200 * time.Millisecond):
		t.Fatal("timed out waiting for automated heartbeat")
	}

	// Manual Ping
	hub.Ping()
	select {
	case msg := <-ch:
		if string(msg) != ": ping\n\n" {
			t.Fatalf("expected manual ping ': ping\\n\\n', got %q", string(msg))
		}
	case <-time.After(50 * time.Millisecond):
		t.Fatal("timed out waiting for manual ping")
	}
}

func TestHandler_HandleSSE_Streaming(t *testing.T) {
	hub := NewHubWithInterval(0)
	defer hub.Close()

	handler := NewHandler(hub)
	server := httptest.NewServer(http.HandlerFunc(handler.HandleSSE))
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL, nil)
	if err != nil {
		t.Fatalf("failed to create request: %v", err)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("failed to connect to SSE stream: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200, got %d", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Errorf("expected Content-Type text/event-stream, got %s", ct)
	}
	if cc := resp.Header.Get("Cache-Control"); cc != "no-cache" {
		t.Errorf("expected Cache-Control no-cache, got %s", cc)
	}

	// Wait for registration
	time.Sleep(20 * time.Millisecond)
	if hub.ClientCount() != 1 {
		t.Fatalf("expected 1 active client in hub, got %d", hub.ClientCount())
	}

	// Broadcast an event through the handler
	saleData := map[string]interface{}{
		"sale_id":     "s-live-1",
		"total_cents": 125000,
	}
	if err := handler.BroadcastSale(saleData); err != nil {
		t.Fatalf("failed to broadcast sale: %v", err)
	}

	// Read lines from SSE stream
	scanner := bufio.NewScanner(resp.Body)
	var lines []string
	readDone := make(chan struct{})

	go func() {
		for scanner.Scan() {
			line := scanner.Text()
			lines = append(lines, line)
			if len(lines) >= 2 {
				close(readDone)
				return
			}
		}
	}()

	select {
	case <-readDone:
		if lines[0] != "event: sale.created" {
			t.Errorf("expected event: sale.created, got %q", lines[0])
		}
		if !strings.HasPrefix(lines[1], "data: ") {
			t.Errorf("expected data line, got %q", lines[1])
		}
		if !strings.Contains(lines[1], "s-live-1") {
			t.Errorf("expected payload to contain s-live-1, got %q", lines[1])
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("timed out waiting for event on SSE HTTP response stream")
	}

	// Cancel context to cleanly disconnect client
	cancel()
	time.Sleep(30 * time.Millisecond)

	if hub.ClientCount() != 0 {
		t.Fatalf("expected client to be unregistered after disconnect, got count %d", hub.ClientCount())
	}
}

func TestHandler_HandleSSE_MethodNotAllowed(t *testing.T) {
	hub := NewHubWithInterval(0)
	defer hub.Close()

	handler := NewHandler(hub)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/realtime/sales", nil)
	rec := httptest.NewRecorder()

	handler.HandleSSE(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected status 405, got %d", rec.Code)
	}
}

type nonFlusherWriter struct {
	http.ResponseWriter
}

func TestHandler_HandleSSE_NonFlusher(t *testing.T) {
	hub := NewHubWithInterval(0)
	defer hub.Close()

	handler := NewHandler(hub)
	rec := httptest.NewRecorder()
	wrapped := nonFlusherWriter{ResponseWriter: rec}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/realtime/sales", nil)
	handler.HandleSSE(wrapped, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected status 500 when Flusher is not supported, got %d", rec.Code)
	}
}
