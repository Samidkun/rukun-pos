package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"rukun.pos/backend/internal/store"
)

type mockPullSyncer struct {
	processPullFn func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error)
}

func (m *mockPullSyncer) ProcessPull(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
	return m.processPullFn(ctx, req)
}

func TestPullHandler_ValidationAndDefaults(t *testing.T) {
	t.Run("rejects non-GET methods", func(t *testing.T) {
		h := NewHandler(nil, &mockPullSyncer{})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/pull", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("expected status 405, got %d", rec.Code)
		}
	})

	t.Run("rejects non-numeric since parameter", func(t *testing.T) {
		h := NewHandler(nil, &mockPullSyncer{})
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?since=invalid", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "invalid since query parameter") {
			t.Errorf("expected error message to mention invalid since, got: %s", rec.Body.String())
		}
	})

	t.Run("rejects negative since parameter", func(t *testing.T) {
		h := NewHandler(nil, &mockPullSyncer{})
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?since=-10", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d", rec.Code)
		}
	})

	t.Run("rejects non-numeric catalog_version parameter", func(t *testing.T) {
		h := NewHandler(nil, &mockPullSyncer{})
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?catalog_version=abc", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "invalid catalog_version query parameter") {
			t.Errorf("expected error message to mention invalid catalog_version, got: %s", rec.Body.String())
		}
	})

	t.Run("rejects negative catalog_version parameter", func(t *testing.T) {
		h := NewHandler(nil, &mockPullSyncer{})
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?catalog_version=-1", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d", rec.Code)
		}
	})

	t.Run("rejects invalid limit parameter", func(t *testing.T) {
		for _, invalidLimit := range []string{"xyz", "0", "-5"} {
			h := NewHandler(nil, &mockPullSyncer{})
			req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?limit="+invalidLimit, nil)
			rec := httptest.NewRecorder()

			h.HandlePull(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected status 400 for limit=%s, got %d", invalidLimit, rec.Code)
			}
		}
	})

	t.Run("applies default parameters when omitted", func(t *testing.T) {
		var receivedReq *PullRequest
		mock := &mockPullSyncer{
			processPullFn: func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
				receivedReq = req
				return &store.SyncPullResponse{
					Events:                []store.Event{},
					NextSince:             0,
					CurrentCatalogVersion: 1,
					CatalogVersion:        1,
					HasMore:               false,
				}, nil
			},
		}

		h := NewHandler(nil, mock)
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d", rec.Code)
		}
		if receivedReq == nil {
			t.Fatal("expected pull syncer to receive request")
		}
		if receivedReq.Since != 0 {
			t.Errorf("expected default since=0, got %d", receivedReq.Since)
		}
		if receivedReq.CatalogVersion != 0 {
			t.Errorf("expected default catalog_version=0, got %d", receivedReq.CatalogVersion)
		}
		if receivedReq.Limit != 100 {
			t.Errorf("expected default limit=100, got %d", receivedReq.Limit)
		}
	})

	t.Run("clamps limit above 500 to 500", func(t *testing.T) {
		var receivedLimit int
		mock := &mockPullSyncer{
			processPullFn: func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
				receivedLimit = req.Limit
				return &store.SyncPullResponse{
					Events:                []store.Event{},
					NextSince:             0,
					CurrentCatalogVersion: 1,
					CatalogVersion:        1,
				}, nil
			},
		}

		h := NewHandler(nil, mock)
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?limit=9999", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d", rec.Code)
		}
		if receivedLimit != 500 {
			t.Errorf("expected clamped limit=500, got %d", receivedLimit)
		}
	})

	t.Run("returns 503 if puller is nil", func(t *testing.T) {
		h := NewHandler(nil) // no puller provided
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("expected status 503, got %d", rec.Code)
		}
	})

	t.Run("returns 500 when puller returns error", func(t *testing.T) {
		mock := &mockPullSyncer{
			processPullFn: func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
				return nil, errors.New("db query failure")
			},
		}

		h := NewHandler(nil, mock)
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusInternalServerError {
			t.Fatalf("expected status 500, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "db query failure") {
			t.Errorf("expected response body to contain error detail, got: %s", rec.Body.String())
		}
	})
}

func TestPullHandler_ResponseSchemaAndCatalog(t *testing.T) {
	category := "Minuman"
	mockProducts := []store.ProductCatalogItem{
		{
			ID:             "prod-1",
			Name:           "Kopi Tubruk",
			Category:       &category,
			PriceCents:     15000,
			BaseStock:      0,
			CatalogVersion: 88,
			Deleted:        false,
		},
	}

	t.Run("returns 200 with catalog when client catalog is outdated", func(t *testing.T) {
		mock := &mockPullSyncer{
			processPullFn: func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
				return &store.SyncPullResponse{
					Events: []store.Event{
						{
							ServerSeq:  1542,
							EventID:    "evt-remote-1",
							TerminalID: "T02",
							DeviceID:   "dev-2",
							EntityType: "sale",
							EntityID:   "sale-2",
							Op:         "create",
							Payload:    json.RawMessage(`{"total_cents":15000}`),
						},
					},
					Catalog:               mockProducts,
					NextSince:             1542,
					CurrentCatalogVersion: 88,
					CatalogVersion:        88,
					HasMore:               false,
				}, nil
			},
		}

		h := NewHandler(nil, mock)
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?since=1042&catalog_version=87", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d: %s", rec.Code, rec.Body.String())
		}

		var rawMap map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &rawMap); err != nil {
			t.Fatalf("failed to decode json map: %v", err)
		}

		// Verify JSON keys per Spec §5.2
		for _, key := range []string{"events", "catalog", "next_since", "current_catalog_version", "has_more"} {
			if _, exists := rawMap[key]; !exists {
				t.Errorf("expected response JSON to contain key %q", key)
			}
		}

		var resp store.SyncPullResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to unmarshal typed response: %v", err)
		}

		if len(resp.Events) != 1 || resp.Events[0].ServerSeq != 1542 {
			t.Errorf("unexpected events in response: %+v", resp.Events)
		}
		if resp.NextSince != 1542 {
			t.Errorf("expected next_since 1542, got %d", resp.NextSince)
		}
		if resp.CurrentCatalogVersion != 88 {
			t.Errorf("expected current_catalog_version 88, got %d", resp.CurrentCatalogVersion)
		}
		if resp.HasMore != false {
			t.Errorf("expected has_more false, got %v", resp.HasMore)
		}
		if len(resp.Catalog) != 1 || resp.Catalog[0].ID != "prod-1" {
			t.Errorf("expected catalog with 1 product, got %+v", resp.Catalog)
		}
	})

	t.Run("returns catalog as null when client catalog is up to date", func(t *testing.T) {
		mock := &mockPullSyncer{
			processPullFn: func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
				return &store.SyncPullResponse{
					Events:                []store.Event{},
					Catalog:               nil,
					NextSince:             1042,
					CurrentCatalogVersion: 88,
					CatalogVersion:        88,
					HasMore:               false,
				}, nil
			},
		}

		h := NewHandler(nil, mock)
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?since=1042&catalog_version=88", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d: %s", rec.Code, rec.Body.String())
		}

		var rawMap map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &rawMap); err != nil {
			t.Fatalf("failed to decode json map: %v", err)
		}

		if rawMap["catalog"] != nil {
			t.Errorf("expected catalog to be null in JSON, got %v", rawMap["catalog"])
		}
	})
}

func TestPullHandler_CursorPagination(t *testing.T) {
	t.Run("next_since equals since when no events returned", func(t *testing.T) {
		mock := &mockPullSyncer{
			processPullFn: func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
				nextSince := req.Since
				return &store.SyncPullResponse{
					Events:                []store.Event{},
					Catalog:               nil,
					NextSince:             nextSince,
					CurrentCatalogVersion: 1,
					HasMore:               false,
				}, nil
			},
		}

		h := NewHandler(nil, mock)
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?since=500", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		var resp store.SyncPullResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to decode json: %v", err)
		}

		if resp.NextSince != 500 {
			t.Errorf("expected next_since=500, got %d", resp.NextSince)
		}
		if resp.HasMore != false {
			t.Errorf("expected has_more=false, got %v", resp.HasMore)
		}
	})

	t.Run("has_more is true when returned events count equals limit", func(t *testing.T) {
		events := make([]store.Event, 5)
		for i := 0; i < 5; i++ {
			events[i] = store.Event{
				ServerSeq:  int64(100 + i + 1),
				EventID:    fmt.Sprintf("e-%d", i+1),
				EntityType: "sale",
				Op:         "create",
				Payload:    json.RawMessage(`{}`),
			}
		}

		mock := &mockPullSyncer{
			processPullFn: func(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
				return &store.SyncPullResponse{
					Events:                events,
					Catalog:               nil,
					NextSince:             events[len(events)-1].ServerSeq,
					CurrentCatalogVersion: 1,
					HasMore:               len(events) == req.Limit,
				}, nil
			},
		}

		h := NewHandler(nil, mock)
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?since=100&limit=5", nil)
		rec := httptest.NewRecorder()

		h.HandlePull(rec, req)

		var resp store.SyncPullResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to decode json: %v", err)
		}

		if resp.NextSince != 105 {
			t.Errorf("expected next_since=105, got %d", resp.NextSince)
		}
		if resp.HasMore != true {
			t.Errorf("expected has_more=true, got %v", resp.HasMore)
		}
	})
}

func TestPullService_LiveDB(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	pool, err := store.ConnectDB(ctx, "")
	if err != nil {
		t.Skipf("PostgreSQL is not reachable (%v); skipping live DB integration test", err)
		return
	}
	defer pool.Close()

	if err := store.RunMigrations(pool); err != nil {
		t.Fatalf("failed to run migrations: %v", err)
	}

	uniqueSuffix := fmt.Sprintf("%d", time.Now().UnixNano())

	// Seed a test product
	productID := "prod-pull-" + uniqueSuffix
	_, err = pool.Exec(ctx, `
INSERT INTO products (id, name, category, price_cents, deleted, catalog_version)
VALUES ($1, 'Kopi Susu Gula Aren', 'Minuman', 20000, false, 2)
ON CONFLICT (id) DO NOTHING;
`, productID)
	if err != nil {
		t.Fatalf("failed to seed product: %v", err)
	}

	// Update catalog_version to 2
	_, err = pool.Exec(ctx, `
UPDATE catalog_version SET version = 2, updated_at = now() WHERE id = 1;
`)
	if err != nil {
		t.Fatalf("failed to update catalog_version: %v", err)
	}

	// Seed an event
	eventID := "evt-pull-" + uniqueSuffix
	var seededSeq int64
	err = pool.QueryRow(ctx, `
INSERT INTO events (event_id, terminal_id, device_id, entity_type, entity_id, op, payload)
VALUES ($1, 'T01', 'dev-pull', 'sale', 'sale-1', 'create', '{"total_cents":20000}')
RETURNING server_seq;
`, eventID).Scan(&seededSeq)
	if err != nil {
		t.Fatalf("failed to seed event: %v", err)
	}

	pullService := NewPullService(pool)

	// 1. Pull with client catalog_version = 1 (outdated): should receive catalog
	resp, err := pullService.ProcessPull(ctx, &PullRequest{
		Since:          seededSeq - 1,
		CatalogVersion: 1,
		Limit:          10,
	})
	if err != nil {
		t.Fatalf("ProcessPull failed: %v", err)
	}

	if resp.CurrentCatalogVersion < 2 {
		t.Errorf("expected CurrentCatalogVersion >= 2, got %d", resp.CurrentCatalogVersion)
	}
	if len(resp.Events) == 0 {
		t.Fatalf("expected at least 1 event, got 0")
	}
	if resp.NextSince < seededSeq {
		t.Errorf("expected next_since >= %d, got %d", seededSeq, resp.NextSince)
	}
	if resp.Catalog == nil || len(resp.Catalog) == 0 {
		t.Errorf("expected catalog products because client version was 1, got empty catalog")
	}

	// 2. Pull with client catalog_version = 2 (up to date): catalog should be nil
	respUpToDate, err := pullService.ProcessPull(ctx, &PullRequest{
		Since:          seededSeq - 1,
		CatalogVersion: 2,
		Limit:          10,
	})
	if err != nil {
		t.Fatalf("ProcessPull failed for up-to-date client: %v", err)
	}

	if respUpToDate.Catalog != nil {
		t.Errorf("expected nil catalog for up-to-date client, got %v", respUpToDate.Catalog)
	}
}
