package realtime

import (
	"encoding/json"
	"net/http"
)

// Handler handles HTTP requests for Server-Sent Events (SSE).
type Handler struct {
	hub *Hub
}

// NewHandler creates a new SSE HTTP handler backed by the given hub.
func NewHandler(hub *Hub) *Handler {
	return &Handler{hub: hub}
}

// Hub returns the underlying Hub.
func (h *Handler) Hub() *Hub {
	return h.hub
}

// BroadcastSale provides a convenience method to broadcast sale events through this handler's hub.
func (h *Handler) BroadcastSale(data interface{}) error {
	if h.hub == nil {
		return nil
	}
	return h.hub.BroadcastSale(data)
}

// HandleSSE establishes an SSE stream connection with the client (GET /api/v1/realtime/sales).
func (h *Handler) HandleSSE(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "method not allowed"})
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	ch := make(chan []byte, 32)
	h.hub.Register(ch)
	defer h.hub.Unregister(ch)

	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			if _, err := w.Write(msg); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}
