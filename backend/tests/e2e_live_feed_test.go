package tests

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"rukun.pos/backend/internal/realtime"
	"rukun.pos/backend/internal/store"
	syncengine "rukun.pos/backend/internal/sync"
)

type mockLiveSyncer struct {
	broadcaster syncengine.EventBroadcaster
}

func (m *mockLiveSyncer) ProcessPush(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error) {
	resp := &store.SyncPushResponse{
		CatalogVersion: 1,
		ServerSeqMax:   1,
	}

	for _, evt := range req.Events {
		resp.Accepted = append(resp.Accepted, evt.EventID)

		if evt.EntityType == "sale" && m.broadcaster != nil {
			var payload map[string]interface{}
			_ = json.Unmarshal(evt.Payload, &payload)
			_ = m.broadcaster.Broadcast("sale", payload)
		}
	}

	return resp, nil
}

func TestE2E_LiveDashboardFeed(t *testing.T) {
	// 1. Verify static dashboard files exist
	rootDir := filepath.Join("..", "..", "dashboard")
	for _, file := range []string{"index.html", "styles.css", "app.js"} {
		path := filepath.Join(rootDir, file)
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("missing dashboard asset %s: %v", file, err)
		}
		if len(data) == 0 {
			t.Fatalf("dashboard asset %s is empty", file)
		}
	}

	// 2. Setup router with SSE Hub and Mock Syncer with Realtime Broadcaster
	sseHub := realtime.NewHub()
	defer sseHub.Close()

	syncer := &mockLiveSyncer{broadcaster: sseHub}
	syncHandler := syncengine.NewHandler(syncer)
	realtimeHandler := realtime.NewHandler(sseHub)

	r := chi.NewRouter()
	r.Post("/api/v1/sync/push", syncHandler.HandlePush)
	r.Get("/api/v1/realtime/sales", realtimeHandler.HandleSSE)

	ts := httptest.NewServer(r)
	defer ts.Close()

	// 3. Connect SSE client
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ts.URL+"/api/v1/realtime/sales", nil)
	if err != nil {
		t.Fatalf("failed to create SSE request: %v", err)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("SSE connection error: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200 for SSE, got %d", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.Contains(ct, "text/event-stream") {
		t.Fatalf("expected text/event-stream Content-Type, got %q", ct)
	}

	// Channel to receive SSE message
	receivedChan := make(chan string, 1)
	go func() {
		scanner := bufio.NewScanner(resp.Body)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.HasPrefix(line, "data: ") {
				receivedChan <- strings.TrimPrefix(line, "data: ")
				return
			}
		}
	}()

	// 4. Push a new sale transaction via /api/v1/sync/push
	pushBody := `{
		"terminal_id": "T01",
		"device_id": "d-t01",
		"events": [
			{
				"event_id": "e-e2e-live-1",
				"entity_type": "sale",
				"op": "create",
				"payload": {
					"sale_id": "sale-e2e-1",
					"invoice_series": "T01",
					"invoice_number": 42,
					"total_cents": 36000,
					"payment_method": "cash",
					"items": [
						{"name": "Kopi Susu Gula Aren", "qty": 2, "price_cents": 18000}
					]
				}
			}
		]
	}`

	pushResp, err := http.Post(ts.URL+"/api/v1/sync/push", "application/json", strings.NewReader(pushBody))
	if err != nil {
		t.Fatalf("push request failed: %v", err)
	}
	defer pushResp.Body.Close()

	if pushResp.StatusCode != http.StatusOK {
		t.Fatalf("expected status 200 for push, got %d", pushResp.StatusCode)
	}

	// 5. Wait for SSE event broadcast
	select {
	case data := <-receivedChan:
		if !strings.Contains(data, "sale-e2e-1") {
			t.Errorf("expected received SSE payload to contain sale-e2e-1, got %s", data)
		}
		if !strings.Contains(data, "36000") {
			t.Errorf("expected received SSE payload to contain total_cents 36000, got %s", data)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for SSE sale broadcast")
	}
}
