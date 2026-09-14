package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/go-chi/chi/v5"
	"rukun.pos/backend/internal/realtime"
	"rukun.pos/backend/internal/store"
	syncengine "rukun.pos/backend/internal/sync"
)

// In-memory mock syncer simulating PostgreSQL append-only events & materialization
type InMemorySyncEngine struct {
	mu            sync.Mutex
	events        map[string]store.Event // event_id -> event
	sales         map[string]map[string]interface{}
	movements     []map[string]interface{}
	serverSeq     int64
	catalogVer    int64
	broadcaster   syncengine.EventBroadcaster
}

func NewInMemorySyncEngine(broadcaster syncengine.EventBroadcaster) *InMemorySyncEngine {
	return &InMemorySyncEngine{
		events:      make(map[string]store.Event),
		sales:       make(map[string]map[string]interface{}),
		movements:   make([]map[string]interface{}, 0),
		catalogVer:  1,
		broadcaster: broadcaster,
	}
}

func (e *InMemorySyncEngine) ProcessPush(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	resp := &store.SyncPushResponse{
		CatalogVersion: e.catalogVer,
	}

	for _, evt := range req.Events {
		// Idempotency check: duplicate event_id is dropped gracefully
		if _, exists := e.events[evt.EventID]; exists {
			resp.Accepted = append(resp.Accepted, evt.EventID)
			continue
		}

		e.serverSeq++
		evt.ServerSeq = e.serverSeq
		e.events[evt.EventID] = evt
		resp.Accepted = append(resp.Accepted, evt.EventID)

		// Materialize sales
		if evt.EntityType == "sale" && evt.Op == "create" {
			var sale map[string]interface{}
			_ = json.Unmarshal(evt.Payload, &sale)
			e.sales[evt.EntityID] = sale

			if items, ok := sale["items"].([]interface{}); ok {
				for _, rawItem := range items {
					it := rawItem.(map[string]interface{})
					qty := int(it["qty"].(float64))
					e.movements = append(e.movements, map[string]interface{}{
						"product_id": it["product_id"],
						"delta":      -qty,
						"sale_id":    sale["sale_id"],
					})
				}
			}

			if e.broadcaster != nil {
				_ = e.broadcaster.Broadcast("sale", sale)
			}
		}
	}

	resp.ServerSeqMax = e.serverSeq
	return resp, nil
}

func (e *InMemorySyncEngine) ProcessPull(ctx context.Context, req *syncengine.PullRequest) (*store.SyncPullResponse, error) {
	e.mu.Lock()
	defer e.mu.Unlock()

	pulledEvents := make([]store.Event, 0)
	var maxSeq int64 = req.Since

	for _, evt := range e.events {
		if evt.ServerSeq > req.Since {
			pulledEvents = append(pulledEvents, evt)
			if evt.ServerSeq > maxSeq {
				maxSeq = evt.ServerSeq
			}
		}
	}

	return &store.SyncPullResponse{
		Events:                pulledEvents,
		NextSince:             maxSeq,
		CurrentCatalogVersion: e.catalogVer,
		HasMore:               false,
	}, nil
}

func TestMultiTerminalSimultaneousOfflineConvergence(t *testing.T) {
	sseHub := realtime.NewHub()
	defer sseHub.Close()

	engine := NewInMemorySyncEngine(sseHub)
	syncHandler := syncengine.NewHandler(engine, engine)

	r := chi.NewRouter()
	r.Post("/api/v1/sync/push", syncHandler.HandlePush)
	r.Get("/api/v1/sync/pull", syncHandler.HandlePull)

	ts := httptest.NewServer(r)
	defer ts.Close()

	// SCENARIO:
	// Initial stock for 'prod-kopi-last' = 1 unit.
	// Terminal A (T01) and Terminal B (T02) are both offline.
	// Both sell 1 unit of 'prod-kopi-last' to physical customers.

	t1EventID := "evt-t01-sale-001"
	t1Payload := `{
		"terminal_id": "T01",
		"device_id": "dev-t01",
		"events": [{
			"event_id": "` + t1EventID + `",
			"entity_type": "sale",
			"entity_id": "sale-t01-001",
			"op": "create",
			"hlc": "1766000000100-0-dev-t01",
			"payload": {
				"sale_id": "sale-t01-001",
				"invoice_series": "T01",
				"invoice_number": 1,
				"total_cents": 20000,
				"payment_method": "cash",
				"items": [{"product_id": "prod-kopi-last", "name": "Kopi Terakhir", "qty": 1, "price_cents": 20000}]
			}
		}]
	}`

	t2EventID := "evt-t02-sale-001"
	t2Payload := `{
		"terminal_id": "T02",
		"device_id": "dev-t02",
		"events": [{
			"event_id": "` + t2EventID + `",
			"entity_type": "sale",
			"entity_id": "sale-t02-001",
			"op": "create",
			"hlc": "1766000000105-0-dev-t02",
			"payload": {
				"sale_id": "sale-t02-001",
				"invoice_series": "T02",
				"invoice_number": 1,
				"total_cents": 20000,
				"payment_method": "cash",
				"items": [{"product_id": "prod-kopi-last", "name": "Kopi Terakhir", "qty": 1, "price_cents": 20000}]
			}
		}]
	}`

	// 1. Both terminals reconnect simultaneously -> Push concurrently
	var wg sync.WaitGroup
	errs := make(chan error, 4)

	pushFunc := func(body string) {
		defer wg.Done()
		resp, err := http.Post(ts.URL+"/api/v1/sync/push", "application/json", bytes.NewReader([]byte(body)))
		if err != nil {
			errs <- err
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			errs <- fmt.Errorf("unexpected push status: %d", resp.StatusCode)
		}
	}

	wg.Add(2)
	go pushFunc(t1Payload)
	go pushFunc(t2Payload)
	wg.Wait()

	close(errs)
	for err := range errs {
		t.Fatalf("concurrent push failure: %v", err)
	}

	// 2. Retry pushes (simulating unstable network duplicate retries)
	wg.Add(2)
	go pushFunc(t1Payload)
	go pushFunc(t2Payload)
	wg.Wait()

	// 3. Verify server state: Zero duplicates, exactly 2 sales, total revenue 40.000
	if len(engine.events) != 2 {
		t.Fatalf("expected 2 unique events in store, got %d", len(engine.events))
	}
	if len(engine.sales) != 2 {
		t.Fatalf("expected 2 materialized sales, got %d", len(engine.sales))
	}

	var totalRevenue int64
	for _, sale := range engine.sales {
		totalRevenue += int64(sale["total_cents"].(float64))
	}
	if totalRevenue != 40000 {
		t.Fatalf("expected total revenue Rp 40.000, got %d", totalRevenue)
	}

	// 4. Terminal A pulls updates: receives Terminal B's event
	pullResp, err := http.Get(ts.URL + "/api/v1/sync/pull?since=0&catalog_version=1")
	if err != nil {
		t.Fatalf("pull failed: %v", err)
	}
	defer pullResp.Body.Close()

	var pullData struct {
		Events []store.Event `json:"events"`
	}
	_ = json.NewDecoder(pullResp.Body).Decode(&pullData)

	if len(pullData.Events) != 2 {
		t.Fatalf("expected 2 events in pull, got %d", len(pullData.Events))
	}

	// 5. Verify Stock Convergence and Oversold Condition:
	// Base stock: 1
	// Total delta from movements: -1 (Terminal A) + -1 (Terminal B) = -2
	// Final stock: 1 - 2 = -1 (Oversold detected gracefully, no crash, no deleted sales!)
	var totalDelta int
	for _, m := range engine.movements {
		if m["product_id"] == "prod-kopi-last" {
			totalDelta += m["delta"].(int)
		}
	}
	finalStock := 1 + totalDelta
	if finalStock != -1 {
		t.Fatalf("expected final stock to be -1 (oversold), got %d", finalStock)
	}
}
