package store

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/pressly/goose/v3"
	"rukun.pos/backend/migrations"
)

func TestMigrationSchema(t *testing.T) {
	data, err := migrations.FS.ReadFile("00001_init_schema.sql")
	if err != nil {
		t.Fatalf("failed to read 00001_init_schema.sql: %v", err)
	}

	content := string(data)
	requiredKeywords := []string{
		"-- +goose Up",
		"-- +goose Down",
		"CREATE TABLE IF NOT EXISTS events",
		"CREATE TABLE IF NOT EXISTS products",
		"CREATE TABLE IF NOT EXISTS sales",
		"CREATE TABLE IF NOT EXISTS sale_items",
		"CREATE TABLE IF NOT EXISTS stock_movements",
		"CREATE TABLE IF NOT EXISTS catalog_version",
		"CREATE TABLE IF NOT EXISTS devices",
		"event_id TEXT NOT NULL UNIQUE",
		"CONSTRAINT uq_terminal_invoice UNIQUE (terminal_id, invoice_series, invoice_number)",
	}

	for _, kw := range requiredKeywords {
		if !strings.Contains(content, kw) {
			t.Errorf("migration SQL missing required keyword: %q", kw)
		}
	}

	// Verify goose can parse the migrations from embedded FS
	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatalf("failed to set goose dialect: %v", err)
	}

	migList, err := goose.CollectMigrations(".", 0, 999999)
	if err != nil {
		t.Fatalf("goose failed to collect migrations: %v", err)
	}

	if len(migList) == 0 {
		t.Fatalf("expected at least 1 migration, got 0")
	}

	if migList[0].Version != 1 {
		t.Errorf("expected migration version 1, got %d", migList[0].Version)
	}
}

func TestEventJSONMarshaling(t *testing.T) {
	hlc := "1766000000123-0-dev-1"
	evt := Event{
		ServerSeq:  101,
		EventID:    "evt-uuid-1",
		TerminalID: "T01",
		DeviceID:   "dev-1",
		EntityType: "sale",
		EntityID:   "sale-1",
		Op:         "create",
		Payload:    json.RawMessage(`{"total_cents":25000}`),
		HLC:        &hlc,
		Status:     "applied",
	}

	b, err := json.Marshal(evt)
	if err != nil {
		t.Fatalf("failed to marshal event: %v", err)
	}

	var decoded Event
	if err := json.Unmarshal(b, &decoded); err != nil {
		t.Fatalf("failed to unmarshal event: %v", err)
	}

	if decoded.EventID != evt.EventID {
		t.Errorf("expected EventID %q, got %q", evt.EventID, decoded.EventID)
	}
	if decoded.HLC == nil || *decoded.HLC != hlc {
		t.Errorf("expected HLC %q, got %v", hlc, decoded.HLC)
	}
	if string(decoded.Payload) != string(evt.Payload) {
		t.Errorf("expected Payload %s, got %s", evt.Payload, decoded.Payload)
	}
}

func TestSyncPushRequestResponseJSON(t *testing.T) {
	req := SyncPushRequest{
		TerminalID: "T01",
		DeviceID:   "dev-1",
		Events: []Event{
			{
				EventID:    "e-1",
				EntityType: "sale",
				EntityID:   "s-1",
				Op:         "create",
				Payload:    json.RawMessage(`{"items":[]}`),
			},
		},
	}

	b, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("failed to marshal SyncPushRequest: %v", err)
	}

	var decReq SyncPushRequest
	if err := json.Unmarshal(b, &decReq); err != nil {
		t.Fatalf("failed to unmarshal SyncPushRequest: %v", err)
	}
	if len(decReq.Events) != 1 || decReq.Events[0].EventID != "e-1" {
		t.Errorf("unexpected unmarshaled events: %+v", decReq.Events)
	}

	resp := SyncPushResponse{
		Accepted: []string{"e-1"},
		Rejected: []RejectedEvent{
			{EventID: "e-2", Reason: "unknown_product"},
		},
		ServerSeqMax:   42,
		CatalogVersion: 1,
	}

	respB, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("failed to marshal SyncPushResponse: %v", err)
	}

	var decResp SyncPushResponse
	if err := json.Unmarshal(respB, &decResp); err != nil {
		t.Fatalf("failed to unmarshal SyncPushResponse: %v", err)
	}
	if len(decResp.Accepted) != 1 || decResp.Accepted[0] != "e-1" {
		t.Errorf("unexpected accepted: %+v", decResp.Accepted)
	}
	if len(decResp.Rejected) != 1 || decResp.Rejected[0].Reason != "unknown_product" {
		t.Errorf("unexpected rejected: %+v", decResp.Rejected)
	}
}

func TestStoreEventValidation(t *testing.T) {
	ctx := context.Background()

	// Nil event
	inserted, err := StoreEvent(ctx, nil, nil)
	if err == nil {
		t.Errorf("expected error for nil event, got nil")
	}
	if inserted {
		t.Errorf("expected inserted=false for nil event")
	}

	// Empty event_id
	inserted, err = StoreEvent(ctx, nil, &Event{EventID: ""})
	if err == nil {
		t.Errorf("expected error for empty event_id, got nil")
	}
	if inserted {
		t.Errorf("expected inserted=false for empty event_id")
	}
}

func TestSQLQueryDefinitions(t *testing.T) {
	if !strings.Contains(insertEventQuery, "ON CONFLICT (event_id) DO NOTHING") {
		t.Error("insertEventQuery must include ON CONFLICT (event_id) DO NOTHING clause")
	}
	if !strings.Contains(insertEventQuery, "RETURNING server_seq, received_at") {
		t.Error("insertEventQuery must include RETURNING server_seq, received_at")
	}

	if !strings.Contains(selectEventsAfterSeqQuery, "WHERE server_seq > $1") {
		t.Error("selectEventsAfterSeqQuery must filter by server_seq > $1")
	}
	if !strings.Contains(selectEventsAfterSeqQuery, "ORDER BY server_seq ASC") {
		t.Error("selectEventsAfterSeqQuery must order by server_seq ASC")
	}
}

func TestPostgresStoreIntegration(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	pool, err := ConnectDB(ctx, "")
	if err != nil {
		t.Skipf("PostgreSQL is not reachable (%v); skipping live DB integration test", err)
		return
	}
	defer pool.Close()

	// Apply migrations
	if err := RunMigrations(pool); err != nil {
		t.Fatalf("failed to apply migrations: %v", err)
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("failed to start test transaction: %v", err)
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	testEventID := "test-event-" + time.Now().Format("20060102150405.000000000")
	hlc := "test-hlc-val"
	evt := &Event{
		EventID:    testEventID,
		TerminalID: "T01",
		DeviceID:   "D01",
		EntityType: "sale",
		EntityID:   "S01",
		Op:         "create",
		Payload:    json.RawMessage(`{"total_cents":50000}`),
		HLC:        &hlc,
	}

	// 1. First insert should succeed
	inserted, err := StoreEvent(ctx, tx, evt)
	if err != nil {
		t.Fatalf("StoreEvent failed: %v", err)
	}
	if !inserted {
		t.Fatalf("expected inserted=true for fresh event")
	}
	if evt.ServerSeq <= 0 {
		t.Fatalf("expected valid server_seq > 0, got %d", evt.ServerSeq)
	}
	if evt.ReceivedAt.IsZero() {
		t.Fatalf("expected non-zero received_at")
	}
	if evt.Status != "applied" {
		t.Errorf("expected status 'applied', got %q", evt.Status)
	}

	// 2. Duplicate insert with identical event_id should be skipped idempotently
	dupEvt := &Event{
		EventID:    testEventID,
		TerminalID: "T01",
		DeviceID:   "D01",
		EntityType: "sale",
		EntityID:   "S01",
		Op:         "create",
		Payload:    json.RawMessage(`{"total_cents":50000}`),
	}
	dupInserted, err := StoreEvent(ctx, tx, dupEvt)
	if err != nil {
		t.Fatalf("duplicate StoreEvent returned error: %v", err)
	}
	if dupInserted {
		t.Fatalf("expected inserted=false for duplicate event_id, got true")
	}

	// 3. Query events after seq 0
	events, err := GetEventsAfterSeq(ctx, pool, evt.ServerSeq-1, 10)
	if err != nil {
		t.Fatalf("GetEventsAfterSeq failed: %v", err)
	}
	if len(events) == 0 {
		t.Fatalf("expected at least 1 event returned")
	}
}
