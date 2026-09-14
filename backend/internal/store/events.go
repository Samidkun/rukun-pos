package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Event represents an immutable sync event in the append-only event log.
type Event struct {
	ServerSeq    int64           `json:"server_seq,omitempty"`
	EventID      string          `json:"event_id"`
	TerminalID   string          `json:"terminal_id"`
	DeviceID     string          `json:"device_id"`
	EntityType   string          `json:"entity_type"`
	EntityID     string          `json:"entity_id"`
	Op           string          `json:"op"`
	Payload      json.RawMessage `json:"payload"`
	HLC          *string         `json:"hlc,omitempty"`
	Status       string          `json:"status,omitempty"`
	RejectReason *string         `json:"reject_reason,omitempty"`
	ReceivedAt   time.Time       `json:"received_at,omitempty"`
}

// SyncPushRequest represents the payload from a client push sync operation.
type SyncPushRequest struct {
	TerminalID string  `json:"terminal_id"`
	DeviceID   string  `json:"device_id"`
	Events     []Event `json:"events"`
}

// RejectedEvent details an individual rejected event in push response.
type RejectedEvent struct {
	EventID string `json:"event_id"`
	Reason  string `json:"reason"`
}

// SyncPushResponse represents the acknowledgment payload returned to the client.
type SyncPushResponse struct {
	Accepted       []string        `json:"accepted"`
	Rejected       []RejectedEvent `json:"rejected"`
	ServerSeqMax   int64           `json:"server_seq_max"`
	CatalogVersion int64           `json:"catalog_version"`
}

// SyncPullResponse represents changes sent to a client pulling updates.
type SyncPullResponse struct {
	Events         []Event          `json:"events"`
	Catalog        *json.RawMessage `json:"catalog,omitempty"`
	NextSince      int64            `json:"next_since"`
	HasMore        bool             `json:"has_more"`
	CatalogVersion int64            `json:"catalog_version"`
}

const (
	insertEventQuery = `
INSERT INTO events (
    event_id, terminal_id, device_id, entity_type, entity_id, op, payload, hlc, status, reject_reason
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
ON CONFLICT (event_id) DO NOTHING
RETURNING server_seq, received_at;
`

	selectEventsAfterSeqQuery = `
SELECT server_seq, event_id, terminal_id, device_id, entity_type, entity_id, op, payload, hlc, status, reject_reason, received_at
FROM events
WHERE server_seq > $1
ORDER BY server_seq ASC
LIMIT $2;
`
)

// StoreEvent records an event inside the given transaction.
// Returns inserted = true if newly recorded, or inserted = false if duplicate (idempotent no-op).
func StoreEvent(ctx context.Context, tx pgx.Tx, event *Event) (bool, error) {
	if event == nil {
		return false, errors.New("event cannot be nil")
	}
	if event.EventID == "" {
		return false, errors.New("event_id is required")
	}

	payload := event.Payload
	if len(payload) == 0 {
		payload = json.RawMessage("{}")
	}

	status := event.Status
	if status == "" {
		status = "applied"
	}

	var serverSeq int64
	var receivedAt time.Time

	err := tx.QueryRow(ctx, insertEventQuery,
		event.EventID,
		event.TerminalID,
		event.DeviceID,
		event.EntityType,
		event.EntityID,
		event.Op,
		payload,
		event.HLC,
		status,
		event.RejectReason,
	).Scan(&serverSeq, &receivedAt)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// ponytail: duplicate skipped without returning existing server_seq; fetch if client pull protocol requires replay seq.
			return false, nil
		}
		return false, fmt.Errorf("store event %s: %w", event.EventID, err)
	}

	event.ServerSeq = serverSeq
	event.ReceivedAt = receivedAt
	event.Status = status
	event.Payload = payload
	return true, nil
}

// GetEventsAfterSeq fetches events strictly after afterSeq, ordered by server_seq ascending.
func GetEventsAfterSeq(ctx context.Context, pool *pgxpool.Pool, afterSeq int64, limit int) ([]Event, error) {
	if limit <= 0 {
		limit = 100
	} else if limit > 1000 {
		limit = 1000
	}

	rows, err := pool.Query(ctx, selectEventsAfterSeqQuery, afterSeq, limit)
	if err != nil {
		return nil, fmt.Errorf("query events after seq %d: %w", afterSeq, err)
	}
	defer rows.Close()

	events := make([]Event, 0)
	for rows.Next() {
		var e Event
		if err := rows.Scan(
			&e.ServerSeq,
			&e.EventID,
			&e.TerminalID,
			&e.DeviceID,
			&e.EntityType,
			&e.EntityID,
			&e.Op,
			&e.Payload,
			&e.HLC,
			&e.Status,
			&e.RejectReason,
			&e.ReceivedAt,
		); err != nil {
			return nil, fmt.Errorf("scan event: %w", err)
		}
		events = append(events, e)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate event rows: %w", err)
	}

	return events, nil
}

// StoreEvent provides Store method access to StoreEvent.
func (s *Store) StoreEvent(ctx context.Context, tx pgx.Tx, event *Event) (bool, error) {
	return StoreEvent(ctx, tx, event)
}

// GetEventsAfterSeq provides Store method access to GetEventsAfterSeq.
func (s *Store) GetEventsAfterSeq(ctx context.Context, afterSeq int64, limit int) ([]Event, error) {
	return GetEventsAfterSeq(ctx, s.Pool, afterSeq, limit)
}
