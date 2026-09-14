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

func TestValidator_PushRequest(t *testing.T) {
	tests := []struct {
		name    string
		req     *store.SyncPushRequest
		wantErr error
	}{
		{
			name:    "nil request",
			req:     nil,
			wantErr: ErrNilRequest,
		},
		{
			name: "missing terminal_id",
			req: &store.SyncPushRequest{
				TerminalID: "",
				DeviceID:   "dev-1",
				Events: []store.Event{
					{EventID: "evt-1", EntityType: "sale", Op: "create", Payload: json.RawMessage(`{"sale_id":"s1"}`)},
				},
			},
			wantErr: ErrMissingTerminalID,
		},
		{
			name: "missing device_id",
			req: &store.SyncPushRequest{
				TerminalID: "T01",
				DeviceID:   "",
				Events: []store.Event{
					{EventID: "evt-1", EntityType: "sale", Op: "create", Payload: json.RawMessage(`{"sale_id":"s1"}`)},
				},
			},
			wantErr: ErrMissingDeviceID,
		},
		{
			name: "empty events slice",
			req: &store.SyncPushRequest{
				TerminalID: "T01",
				DeviceID:   "dev-1",
				Events:     []store.Event{},
			},
			wantErr: ErrEmptyEvents,
		},
		{
			name: "valid push request",
			req: &store.SyncPushRequest{
				TerminalID: "T01",
				DeviceID:   "dev-1",
				Events: []store.Event{
					{
						EventID:    "evt-1",
						EntityType: "sale",
						Op:         "create",
						Payload:    json.RawMessage(`{"sale_id":"s1","total_cents":25000}`),
					},
				},
			},
			wantErr: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidatePushRequest(tt.req)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("expected error %v, got %v", tt.wantErr, err)
			}
		})
	}
}

func TestValidator_Event(t *testing.T) {
	tests := []struct {
		name    string
		evt     *store.Event
		wantErr error
	}{
		{
			name:    "nil event",
			evt:     nil,
			wantErr: ErrNilEvent,
		},
		{
			name: "missing event_id",
			evt: &store.Event{
				EventID:    "",
				EntityType: "sale",
				Op:         "create",
				Payload:    json.RawMessage(`{"total_cents":100}`),
			},
			wantErr: ErrMissingEventID,
		},
		{
			name: "missing entity_type",
			evt: &store.Event{
				EventID:    "evt-1",
				EntityType: "",
				Op:         "create",
				Payload:    json.RawMessage(`{"total_cents":100}`),
			},
			wantErr: ErrMissingEntityType,
		},
		{
			name: "missing op",
			evt: &store.Event{
				EventID:    "evt-1",
				EntityType: "sale",
				Op:         "",
				Payload:    json.RawMessage(`{"total_cents":100}`),
			},
			wantErr: ErrMissingOp,
		},
		{
			name: "empty payload",
			evt: &store.Event{
				EventID:    "evt-1",
				EntityType: "sale",
				Op:         "create",
				Payload:    nil,
			},
			wantErr: ErrEmptyPayload,
		},
		{
			name: "payload is empty json object",
			evt: &store.Event{
				EventID:    "evt-1",
				EntityType: "sale",
				Op:         "create",
				Payload:    json.RawMessage(`{}`),
			},
			wantErr: ErrEmptyPayload,
		},
		{
			name: "payload is null literal",
			evt: &store.Event{
				EventID:    "evt-1",
				EntityType: "sale",
				Op:         "create",
				Payload:    json.RawMessage(`null`),
			},
			wantErr: ErrEmptyPayload,
		},
		{
			name: "invalid json payload",
			evt: &store.Event{
				EventID:    "evt-1",
				EntityType: "sale",
				Op:         "create",
				Payload:    json.RawMessage(`{malformed: json`),
			},
			wantErr: ErrInvalidPayload,
		},
		{
			name: "valid event",
			evt: &store.Event{
				EventID:    "evt-1",
				EntityType: "sale",
				Op:         "create",
				Payload:    json.RawMessage(`{"sale_id":"s-1","total_cents":15000}`),
			},
			wantErr: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateEvent(tt.evt)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("expected error %v, got %v", tt.wantErr, err)
			}
		})
	}
}

type mockPushSyncer struct {
	processPushFn func(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error)
}

func (m *mockPushSyncer) ProcessPush(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error) {
	return m.processPushFn(ctx, req)
}

func TestPushHandler_HTTP(t *testing.T) {
	t.Run("rejects non-POST method", func(t *testing.T) {
		handler := NewHandler(&mockPushSyncer{})
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/push", nil)
		rec := httptest.NewRecorder()

		handler.HandlePush(rec, req)

		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("expected status 405, got %d", rec.Code)
		}
	})

	t.Run("rejects malformed json", func(t *testing.T) {
		handler := NewHandler(&mockPushSyncer{})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", strings.NewReader(`{bad-json`))
		rec := httptest.NewRecorder()

		handler.HandlePush(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d", rec.Code)
		}
	})

	t.Run("rejects missing terminal_id", func(t *testing.T) {
		handler := NewHandler(&mockPushSyncer{})
		body := `{"terminal_id":"","device_id":"d1","events":[{"event_id":"e1","entity_type":"sale","op":"create","payload":{"total_cents":100}}]}`
		req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", strings.NewReader(body))
		rec := httptest.NewRecorder()

		handler.HandlePush(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "terminal_id is required") {
			t.Errorf("expected error message to mention terminal_id, got: %s", rec.Body.String())
		}
	})

	t.Run("rejects empty events array", func(t *testing.T) {
		handler := NewHandler(&mockPushSyncer{})
		body := `{"terminal_id":"T01","device_id":"d1","events":[]}`
		req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", strings.NewReader(body))
		rec := httptest.NewRecorder()

		handler.HandlePush(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "events list cannot be empty") {
			t.Errorf("expected error message to mention empty events, got: %s", rec.Body.String())
		}
	})

	t.Run("returns 503 if syncer is nil", func(t *testing.T) {
		handler := NewHandler(nil)
		body := `{"terminal_id":"T01","device_id":"d1","events":[{"event_id":"e1","entity_type":"sale","op":"create","payload":{"total_cents":100}}]}`
		req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", strings.NewReader(body))
		rec := httptest.NewRecorder()

		handler.HandlePush(rec, req)

		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("expected status 503, got %d", rec.Code)
		}
	})

	t.Run("returns 500 when syncer returns unexpected error", func(t *testing.T) {
		mock := &mockPushSyncer{
			processPushFn: func(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error) {
				return nil, errors.New("db connection timeout")
			},
		}
		handler := NewHandler(mock)
		body := `{"terminal_id":"T01","device_id":"d1","events":[{"event_id":"e1","entity_type":"sale","op":"create","payload":{"total_cents":100}}]}`
		req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", strings.NewReader(body))
		rec := httptest.NewRecorder()

		handler.HandlePush(rec, req)

		if rec.Code != http.StatusInternalServerError {
			t.Fatalf("expected status 500, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "db connection timeout") {
			t.Errorf("expected response to contain error message, got %s", rec.Body.String())
		}
	})

	t.Run("returns 200 OK with push acknowledgment for valid request", func(t *testing.T) {
		mock := &mockPushSyncer{
			processPushFn: func(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error) {
				if req.TerminalID != "T01" || req.DeviceID != "d-a1" {
					t.Errorf("unexpected request header fields: %+v", req)
				}
				if len(req.Events) != 2 {
					t.Errorf("expected 2 events, got %d", len(req.Events))
				}
				return &store.SyncPushResponse{
					Accepted: []string{"e-7f3c"},
					Rejected: []store.RejectedEvent{
						{EventID: "e-9a", Reason: "unknown_product"},
					},
					ServerSeqMax:   1042,
					CatalogVersion: 1,
				}, nil
			},
		}

		handler := NewHandler(mock)
		body := `{
			"terminal_id": "T01",
			"device_id": "d-a1",
			"events": [
				{
					"event_id": "e-7f3c",
					"entity_type": "sale",
					"op": "create",
					"hlc": "1766000000123-0-d-a1",
					"payload": {
						"sale_id": "s-1",
						"invoice_series": "T01",
						"invoice_number": 1,
						"total_cents": 25000,
						"payment_method": "cash",
						"occurred_at": "2026-09-14T10:00:00Z",
						"items": [
							{"id": "item-1", "product_id": "prod-1", "name": "Kopi", "price_cents": 25000, "qty": 1}
						]
					}
				},
				{
					"event_id": "e-9a",
					"entity_type": "sale",
					"op": "create",
					"payload": {"invalid": true}
				}
			]
		}`

		req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", strings.NewReader(body))
		rec := httptest.NewRecorder()

		handler.HandlePush(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d: %s", rec.Code, rec.Body.String())
		}

		contentType := rec.Header().Get("Content-Type")
		if !strings.Contains(contentType, "application/json") {
			t.Errorf("expected Content-Type application/json, got %s", contentType)
		}

		var resp store.SyncPushResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to decode response JSON: %v", err)
		}

		if len(resp.Accepted) != 1 || resp.Accepted[0] != "e-7f3c" {
			t.Errorf("expected accepted [e-7f3c], got %+v", resp.Accepted)
		}
		if len(resp.Rejected) != 1 || resp.Rejected[0].EventID != "e-9a" || resp.Rejected[0].Reason != "unknown_product" {
			t.Errorf("expected rejected [e-9a], got %+v", resp.Rejected)
		}
		if resp.ServerSeqMax != 1042 {
			t.Errorf("expected server_seq_max 1042, got %d", resp.ServerSeqMax)
		}
		if resp.CatalogVersion != 1 {
			t.Errorf("expected catalog_version 1, got %d", resp.CatalogVersion)
		}
	})
}

func TestPushService_LiveDB(t *testing.T) {
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

	service := NewPushService(pool)

	uniqueSuffix := fmt.Sprintf("%d", time.Now().UnixNano())
	testEventID := "evt-push-" + uniqueSuffix
	testSaleID := "sale-push-" + uniqueSuffix
	testProductID := "prod-test-" + uniqueSuffix
	hlc := "1766000000123-0-d-test"

	req := &store.SyncPushRequest{
		TerminalID: "T01",
		DeviceID:   "dev-test",
		Events: []store.Event{
			{
				EventID:    testEventID,
				TerminalID: "T01",
				DeviceID:   "dev-test",
				EntityType: "sale",
				EntityID:   testSaleID,
				Op:         "create",
				HLC:        &hlc,
				Payload: json.RawMessage(fmt.Sprintf(`{
					"sale_id": "%s",
					"invoice_series": "T01",
					"invoice_number": %d,
					"total_cents": 50000,
					"payment_method": "cash",
					"occurred_at": "2026-09-14T10:30:00Z",
					"items": [
						{"id": "item-%s", "product_id": "%s", "name": "Kopi Susu", "price_cents": 25000, "qty": 2}
					]
				}`, testSaleID, time.Now().Unix()%1000000, uniqueSuffix, testProductID)),
			},
		},
	}

	// 1. First push: should succeed and materialize
	resp, err := service.ProcessPush(ctx, req)
	if err != nil {
		t.Fatalf("ProcessPush failed: %v", err)
	}

	if len(resp.Accepted) != 1 || resp.Accepted[0] != testEventID {
		t.Fatalf("expected accepted [%s], got %+v", testEventID, resp.Accepted)
	}
	if len(resp.Rejected) != 0 {
		t.Fatalf("expected 0 rejected, got %+v", resp.Rejected)
	}
	if resp.ServerSeqMax <= 0 {
		t.Errorf("expected ServerSeqMax > 0, got %d", resp.ServerSeqMax)
	}

	// Verify database state
	var eventStatus string
	err = pool.QueryRow(ctx, "SELECT status FROM events WHERE event_id = $1", testEventID).Scan(&eventStatus)
	if err != nil {
		t.Fatalf("failed to query inserted event: %v", err)
	}
	if eventStatus != "applied" {
		t.Errorf("expected event status 'applied', got %q", eventStatus)
	}

	var saleTotal int64
	err = pool.QueryRow(ctx, "SELECT total_cents FROM sales WHERE id = $1", testSaleID).Scan(&saleTotal)
	if err != nil {
		t.Fatalf("failed to query materialized sale: %v", err)
	}
	if saleTotal != 50000 {
		t.Errorf("expected sale total 50000, got %d", saleTotal)
	}

	var itemQty int
	err = pool.QueryRow(ctx, "SELECT qty FROM sale_items WHERE sale_id = $1", testSaleID).Scan(&itemQty)
	if err != nil {
		t.Fatalf("failed to query materialized sale item: %v", err)
	}
	if itemQty != 2 {
		t.Errorf("expected sale item qty 2, got %d", itemQty)
	}

	var smDelta int
	var smReason string
	err = pool.QueryRow(ctx, "SELECT delta, reason FROM stock_movements WHERE sale_id = $1", testSaleID).Scan(&smDelta, &smReason)
	if err != nil {
		t.Fatalf("failed to query stock movement: %v", err)
	}
	if smDelta != -2 {
		t.Errorf("expected stock movement delta -2, got %d", smDelta)
	}
	if smReason != "sale" {
		t.Errorf("expected stock movement reason 'sale', got %q", smReason)
	}

	var lastSeenSeq int64
	err = pool.QueryRow(ctx, "SELECT last_seen_seq FROM devices WHERE device_id = $1", "dev-test").Scan(&lastSeenSeq)
	if err != nil {
		t.Fatalf("failed to query devices tracker: %v", err)
	}
	if lastSeenSeq <= 0 {
		t.Errorf("expected device last_seen_seq > 0, got %d", lastSeenSeq)
	}

	// 2. Duplicate push: re-pushing the same event should acknowledge without error
	dupResp, err := service.ProcessPush(ctx, req)
	if err != nil {
		t.Fatalf("duplicate ProcessPush failed: %v", err)
	}
	if len(dupResp.Accepted) != 1 || dupResp.Accepted[0] != testEventID {
		t.Fatalf("expected duplicate to be acknowledged in accepted [%s], got %+v", testEventID, dupResp.Accepted)
	}

	// 3. Rejected event: push event with unparseable payload
	badEventID := "evt-bad-" + uniqueSuffix
	badReq := &store.SyncPushRequest{
		TerminalID: "T01",
		DeviceID:   "dev-test",
		Events: []store.Event{
			{
				EventID:    badEventID,
				TerminalID: "T01",
				DeviceID:   "dev-test",
				EntityType: "sale",
				EntityID:   "bad-sale",
				Op:         "create",
				Payload:    json.RawMessage(`{"items": "not-an-array"}`),
			},
		},
	}
	badResp, err := service.ProcessPush(ctx, badReq)
	if err != nil {
		t.Fatalf("bad request ProcessPush returned unexpected error: %v", err)
	}
	if len(badResp.Rejected) != 1 || badResp.Rejected[0].EventID != badEventID {
		t.Fatalf("expected rejected event [%s], got %+v", badEventID, badResp.Rejected)
	}

	var badStatus, rejectReason string
	err = pool.QueryRow(ctx, "SELECT status, reject_reason FROM events WHERE event_id = $1", badEventID).Scan(&badStatus, &rejectReason)
	if err != nil {
		t.Fatalf("failed to query rejected event from db: %v", err)
	}
	if badStatus != "rejected" {
		t.Errorf("expected status 'rejected', got %q", badStatus)
	}
	if !strings.Contains(rejectReason, "invalid sale payload") {
		t.Errorf("expected reject_reason to mention invalid sale payload, got %q", rejectReason)
	}
}

type mockEventBroadcaster struct {
	eventType string
	data      interface{}
	called    bool
}

func (m *mockEventBroadcaster) Broadcast(eventType string, data interface{}) error {
	m.eventType = eventType
	m.data = data
	m.called = true
	return nil
}

func TestPushService_BroadcastSale(t *testing.T) {
	mock := &mockEventBroadcaster{}
	svc := NewPushService(nil, mock)

	evt := &store.Event{
		EventID:    "evt-bc-1",
		TerminalID: "Kasir 1",
		DeviceID:   "dev-01",
		EntityType: "sale",
		Op:         "create",
	}

	sale := &SalePayload{
		SaleID:        "sale-bc-1",
		InvoiceSeries: "INV-2026",
		InvoiceNumber: 42,
		TotalCents:    150000,
		PaymentMethod: "cash",
		OccurredAt:    "2026-09-14T12:00:00Z",
		Items: []SaleItemData{
			{ID: "item-1", ProductID: "p1", Name: "Kopi Susu", PriceCents: 150000, Qty: 1},
		},
	}

	err := svc.BroadcastSale(evt, sale, 101)
	if err != nil {
		t.Fatalf("unexpected BroadcastSale error: %v", err)
	}

	if !mock.called {
		t.Fatal("expected broadcaster to be called")
	}
	if mock.eventType != "sale.created" {
		t.Fatalf("expected eventType 'sale.created', got %s", mock.eventType)
	}

	payload, ok := mock.data.(SaleBroadcast)
	if !ok {
		t.Fatalf("expected payload to be SaleBroadcast, got %T", mock.data)
	}
	if payload.SaleID != "sale-bc-1" || payload.TotalCents != 150000 || payload.ServerSeq != 101 {
		t.Errorf("unexpected broadcast payload: %+v", payload)
	}

	// Test nil broadcaster doesn't error
	svcNil := NewPushService(nil)
	if err := svcNil.BroadcastSale(evt, sale, 102); err != nil {
		t.Errorf("expected nil broadcaster to return nil error, got %v", err)
	}

	// Test Handler SetBroadcaster forwards to PushService
	handler := NewHandler(svcNil)
	handler.SetBroadcaster(mock)
	if svcNil.broadcaster == nil {
		t.Error("expected Handler.SetBroadcaster to update underlying PushService broadcaster")
	}
}

