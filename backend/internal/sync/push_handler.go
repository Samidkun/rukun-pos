package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"rukun.pos/backend/internal/store"
)

// SalePayload models the deserialized payload of a sale.create event.
type SalePayload struct {
	SaleID        string         `json:"sale_id"`
	InvoiceSeries string         `json:"invoice_series"`
	InvoiceNumber int64          `json:"invoice_number"`
	TotalCents    int64          `json:"total_cents"`
	PaymentMethod string         `json:"payment_method"`
	OccurredAt    string         `json:"occurred_at"`
	Items         []SaleItemData `json:"items"`
}

// SaleItemData represents an item line within a sale payload.
type SaleItemData struct {
	ID         string `json:"id"`
	ProductID  string `json:"product_id"`
	Name       string `json:"name"`
	PriceCents int64  `json:"price_cents"`
	Qty        int    `json:"qty"`
}

// PushSyncer defines the interface for batch push processing.
type PushSyncer interface {
	ProcessPush(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error)
}

// PushService implements PushSyncer with transactional PostgreSQL materialization.
type PushService struct {
	pool *pgxpool.Pool
}

// NewPushService initializes a new PushService backed by pgxpool.
func NewPushService(pool *pgxpool.Pool) *PushService {
	return &PushService{pool: pool}
}

// ProcessPush applies a batch of sync events transactionally.
func (s *PushService) ProcessPush(ctx context.Context, req *store.SyncPushRequest) (*store.SyncPushResponse, error) {
	if s.pool == nil {
		return nil, errors.New("database connection pool not available")
	}

	resp := &store.SyncPushResponse{
		Accepted: make([]string, 0),
		Rejected: make([]store.RejectedEvent, 0),
	}

	var maxSeq int64

	for i := range req.Events {
		evt := &req.Events[i]
		if evt.TerminalID == "" {
			evt.TerminalID = req.TerminalID
		}
		if evt.DeviceID == "" {
			evt.DeviceID = req.DeviceID
		}

		if err := ValidateEvent(evt); err != nil {
			_ = s.recordRejectedEvent(ctx, evt, err.Error())
			resp.Rejected = append(resp.Rejected, store.RejectedEvent{
				EventID: evt.EventID,
				Reason:  err.Error(),
			})
			continue
		}

		seq, accepted, rejectReason, err := s.processSingleEvent(ctx, evt)
		if err != nil {
			return nil, fmt.Errorf("process event %s: %w", evt.EventID, err)
		}

		if rejectReason != "" {
			resp.Rejected = append(resp.Rejected, store.RejectedEvent{
				EventID: evt.EventID,
				Reason:  rejectReason,
			})
		} else if accepted {
			resp.Accepted = append(resp.Accepted, evt.EventID)
			if seq > maxSeq {
				maxSeq = seq
			}
		}
	}

	// Update device heartbeat & last sequence tracker
	// ponytail: synchronous device updates; upgrade to background channel if write contention occurs under high concurrency.
	_ = s.updateDeviceTracker(ctx, req.DeviceID, req.TerminalID, maxSeq)

	serverSeqMax, catalogVer, err := s.getSyncMeta(ctx)
	if err == nil {
		resp.ServerSeqMax = serverSeqMax
		resp.CatalogVersion = catalogVer
	} else {
		resp.ServerSeqMax = maxSeq
		resp.CatalogVersion = 1
	}

	return resp, nil
}

func (s *PushService) processSingleEvent(ctx context.Context, evt *store.Event) (int64, bool, string, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return 0, false, "", fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	entityID := evt.EntityID
	if entityID == "" {
		entityID = evt.EventID
	}

	var serverSeq int64
	var receivedAt time.Time

	err = tx.QueryRow(ctx, `
INSERT INTO events (
    event_id, terminal_id, device_id, entity_type, entity_id, op, payload, hlc, status, reject_reason
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'applied', NULL)
ON CONFLICT (event_id) DO NOTHING
RETURNING server_seq, received_at;
`, evt.EventID, evt.TerminalID, evt.DeviceID, evt.EntityType, entityID, evt.Op, evt.Payload, evt.HLC).Scan(&serverSeq, &receivedAt)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// Duplicate event: acknowledge without re-materializing
			_ = tx.Rollback(ctx)
			return 0, true, "", nil
		}
		return 0, false, "", fmt.Errorf("insert event: %w", err)
	}

	// Materialize sales if event is sale.create
	if evt.EntityType == "sale" && evt.Op == "create" {
		var sale SalePayload
		if err := json.Unmarshal(evt.Payload, &sale); err != nil {
			_ = tx.Rollback(ctx)
			reason := "invalid sale payload: " + err.Error()
			_ = s.recordRejectedEvent(ctx, evt, reason)
			return 0, false, reason, nil
		}

		saleID := sale.SaleID
		if saleID == "" {
			saleID = entityID
		}
		series := sale.InvoiceSeries
		if series == "" {
			series = evt.TerminalID
		}

		occurredAt := time.Now()
		if sale.OccurredAt != "" {
			if t, parseErr := time.Parse(time.RFC3339Nano, sale.OccurredAt); parseErr == nil {
				occurredAt = t
			} else if t, parseErr := time.Parse(time.RFC3339, sale.OccurredAt); parseErr == nil {
				occurredAt = t
			}
		}

		paymentMethod := sale.PaymentMethod
		if paymentMethod == "" {
			paymentMethod = "cash"
		}

		_, err = tx.Exec(ctx, `
INSERT INTO sales (
    id, invoice_series, invoice_number, terminal_id, total_cents, payment_method, occurred_at, received_at
) VALUES ($1, $2, $3, $4, $5, $6, $7, now())
ON CONFLICT DO NOTHING;
`, saleID, series, sale.InvoiceNumber, evt.TerminalID, sale.TotalCents, paymentMethod, occurredAt)
		if err != nil {
			return 0, false, "", fmt.Errorf("materialize sale %s: %w", saleID, err)
		}

		for idx, item := range sale.Items {
			itemID := item.ID
			if itemID == "" {
				itemID = fmt.Sprintf("%s-%d", saleID, idx+1)
			}

			_, err = tx.Exec(ctx, `
INSERT INTO sale_items (id, sale_id, product_id, name, price_cents, qty)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (id) DO NOTHING;
`, itemID, saleID, item.ProductID, item.Name, item.PriceCents, item.Qty)
			if err != nil {
				return 0, false, "", fmt.Errorf("materialize sale_item %s: %w", itemID, err)
			}

			smID := fmt.Sprintf("sm-%s-%s", saleID, itemID)
			_, err = tx.Exec(ctx, `
INSERT INTO stock_movements (id, product_id, delta, reason, sale_id, hlc, created_at)
VALUES ($1, $2, $3, $4, $5, $6, now())
ON CONFLICT (id) DO NOTHING;
`, smID, item.ProductID, -item.Qty, "sale", saleID, evt.HLC)
			if err != nil {
				return 0, false, "", fmt.Errorf("materialize stock_movement %s: %w", smID, err)
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, false, "", fmt.Errorf("commit tx: %w", err)
	}

	return serverSeq, true, "", nil
}

func (s *PushService) recordRejectedEvent(ctx context.Context, evt *store.Event, reason string) error {
	entityID := evt.EntityID
	if entityID == "" {
		entityID = evt.EventID
	}
	payload := evt.Payload
	if len(payload) == 0 || !json.Valid(payload) {
		payload = []byte("{}")
	}

	_, err := s.pool.Exec(ctx, `
INSERT INTO events (
    event_id, terminal_id, device_id, entity_type, entity_id, op, payload, hlc, status, reject_reason
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'rejected', $9)
ON CONFLICT (event_id) DO UPDATE SET
    status = 'rejected',
    reject_reason = EXCLUDED.reject_reason;
`, evt.EventID, evt.TerminalID, evt.DeviceID, evt.EntityType, entityID, evt.Op, payload, evt.HLC, reason)
	return err
}

func (s *PushService) updateDeviceTracker(ctx context.Context, deviceID, terminalID string, seq int64) error {
	_, err := s.pool.Exec(ctx, `
INSERT INTO devices (device_id, terminal_id, last_seen_seq, last_seen_at)
VALUES ($1, $2, $3, now())
ON CONFLICT (device_id) DO UPDATE SET
    terminal_id = EXCLUDED.terminal_id,
    last_seen_seq = GREATEST(devices.last_seen_seq, EXCLUDED.last_seen_seq),
    last_seen_at = now();
`, deviceID, terminalID, seq)
	return err
}

func (s *PushService) getSyncMeta(ctx context.Context) (int64, int64, error) {
	var maxSeq int64
	var catVer int64

	err := s.pool.QueryRow(ctx, "SELECT COALESCE(MAX(server_seq), 0) FROM events;").Scan(&maxSeq)
	if err != nil {
		return 0, 0, err
	}

	err = s.pool.QueryRow(ctx, "SELECT COALESCE(MAX(version), 1) FROM catalog_version WHERE id = 1;").Scan(&catVer)
	if err != nil {
		catVer = 1
	}

	return maxSeq, catVer, nil
}

// Handler handles HTTP requests for sync endpoints.
type Handler struct {
	syncer PushSyncer
}

// NewHandler constructs an HTTP handler with the given syncer.
func NewHandler(syncer PushSyncer) *Handler {
	return &Handler{syncer: syncer}
}

// HandlePush handles POST /api/v1/sync/push.
func (h *Handler) HandlePush(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "method not allowed"})
		return
	}

	var req store.SyncPushRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 10<<20))
	if err := decoder.Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "malformed request payload: " + err.Error()})
		return
	}

	if err := ValidatePushRequest(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	if h.syncer == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "sync service unavailable"})
		return
	}

	resp, err := h.syncer.ProcessPush(r.Context(), &req)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
