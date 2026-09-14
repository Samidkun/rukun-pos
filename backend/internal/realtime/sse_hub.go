package realtime

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"
)

// Hub manages active SSE client channels with thread-safe fan-out broadcast.
type Hub struct {
	mu             sync.RWMutex
	clients        map[chan []byte]struct{}
	stopCh         chan struct{}
	heartbeatEvery time.Duration
}

// NewHub creates and starts an SSE Hub with the default 15-second heartbeat ticker.
func NewHub() *Hub {
	return NewHubWithInterval(15 * time.Second)
}

// NewHubWithInterval creates an SSE Hub with a custom heartbeat interval.
// Non-positive interval disables automatic heartbeat.
func NewHubWithInterval(interval time.Duration) *Hub {
	h := &Hub{
		clients:        make(map[chan []byte]struct{}),
		stopCh:         make(chan struct{}),
		heartbeatEvery: interval,
	}

	if interval > 0 {
		go h.runHeartbeat(interval)
	}

	return h
}

// Register adds a client channel to the hub's active listener list.
func (h *Hub) Register(ch chan []byte) {
	if ch == nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[ch] = struct{}{}
}

// Unregister removes a client channel from the active listener list.
func (h *Hub) Unregister(ch chan []byte) {
	if ch == nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, ch)
}

// ClientCount returns the number of currently connected SSE clients.
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// Broadcast serializes data to JSON and formats it as an SSE message frame:
// event: <eventType>\ndata: <json>\n\n
// If eventType is empty, the event line is omitted.
func (h *Hub) Broadcast(eventType string, data interface{}) error {
	var raw []byte
	switch v := data.(type) {
	case []byte:
		raw = v
	case string:
		raw = []byte(v)
	default:
		var err error
		raw, err = json.Marshal(data)
		if err != nil {
			return fmt.Errorf("marshal sse data: %w", err)
		}
	}

	msg := FormatSSEMessage(eventType, raw)
	h.BroadcastRaw(msg)
	return nil
}

// BroadcastSale is a typed helper to broadcast sale events with eventType "sale.created".
func (h *Hub) BroadcastSale(data interface{}) error {
	return h.Broadcast("sale.created", data)
}

// BroadcastRaw sends a preformatted byte slice to all registered clients without blocking.
func (h *Hub) BroadcastRaw(msg []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for ch := range h.clients {
		select {
		case ch <- msg:
		default:
			// ponytail: drop slow client frame if buffer is full; upgrade to eviction or queue worker pool if dropped frames affect dashboard accuracy.
		}
	}
}

// Ping sends an SSE comment heartbeat to all connected clients.
func (h *Hub) Ping() {
	h.BroadcastRaw([]byte(": ping\n\n"))
}

// Close stops the heartbeat generator ticker and releases hub resources.
func (h *Hub) Close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	select {
	case <-h.stopCh:
	default:
		close(h.stopCh)
	}
}

func (h *Hub) runHeartbeat(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	pingMsg := []byte(": ping\n\n")
	for {
		select {
		case <-h.stopCh:
			return
		case <-ticker.C:
			h.BroadcastRaw(pingMsg)
		}
	}
}

// FormatSSEMessage formats an SSE payload conforming to the EventSource specification.
func FormatSSEMessage(eventType string, data []byte) []byte {
	var sb strings.Builder
	if eventType != "" {
		sb.WriteString("event: ")
		sb.WriteString(eventType)
		sb.WriteByte('\n')
	}

	lines := bytes.Split(data, []byte("\n"))
	for _, line := range lines {
		sb.WriteString("data: ")
		sb.Write(line)
		sb.WriteByte('\n')
	}
	sb.WriteByte('\n')
	return []byte(sb.String())
}
