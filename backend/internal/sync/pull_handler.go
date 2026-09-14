package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
	"rukun.pos/backend/internal/store"
)

// PullRequest represents parsed query parameters for a delta sync pull.
type PullRequest struct {
	Since          int64
	CatalogVersion int64
	Limit          int
}

// PullSyncer defines the interface for delta sync pull operations.
type PullSyncer interface {
	ProcessPull(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error)
}

// PullService implements PullSyncer using a PostgreSQL connection pool.
type PullService struct {
	pool *pgxpool.Pool
}

// NewPullService instantiates a PullService backed by pgxpool.
func NewPullService(pool *pgxpool.Pool) *PullService {
	return &PullService{pool: pool}
}

// ProcessPull fetches delta events and catalog if client catalog is outdated.
func (s *PullService) ProcessPull(ctx context.Context, req *PullRequest) (*store.SyncPullResponse, error) {
	if s.pool == nil {
		return nil, errors.New("database connection pool not available")
	}

	events, err := store.GetEventsAfterSeq(ctx, s.pool, req.Since, req.Limit)
	if err != nil {
		return nil, fmt.Errorf("fetch events after seq %d: %w", req.Since, err)
	}
	if events == nil {
		events = make([]store.Event, 0)
	}

	currentCatVer, err := store.GetCurrentCatalogVersion(ctx, s.pool)
	if err != nil {
		// ponytail: fallback to catalog version 1 if catalog_version table read fails; upgrade to alerting if table becomes missing.
		currentCatVer = 1
	}

	var catalog []store.ProductCatalogItem
	if req.CatalogVersion < currentCatVer {
		products, err := store.GetActiveProducts(ctx, s.pool)
		if err != nil {
			return nil, fmt.Errorf("fetch active catalog products: %w", err)
		}
		if products == nil {
			products = make([]store.ProductCatalogItem, 0)
		}
		catalog = products
	}

	nextSince := req.Since
	if len(events) > 0 {
		nextSince = events[len(events)-1].ServerSeq
	}

	hasMore := len(events) == req.Limit

	return &store.SyncPullResponse{
		Events:                events,
		Catalog:               catalog,
		NextSince:             nextSince,
		CurrentCatalogVersion: currentCatVer,
		CatalogVersion:        currentCatVer,
		HasMore:               hasMore,
	}, nil
}

// HandlePull handles GET /api/v1/sync/pull.
func (h *Handler) HandlePull(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "method not allowed"})
		return
	}

	q := r.URL.Query()

	var since int64 = 0
	if sinceStr := q.Get("since"); sinceStr != "" {
		val, err := strconv.ParseInt(sinceStr, 10, 64)
		if err != nil || val < 0 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid since query parameter"})
			return
		}
		since = val
	}

	var catalogVersion int64 = 0
	if catVerStr := q.Get("catalog_version"); catVerStr != "" {
		val, err := strconv.ParseInt(catVerStr, 10, 64)
		if err != nil || val < 0 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid catalog_version query parameter"})
			return
		}
		catalogVersion = val
	}

	limit := 100
	if limitStr := q.Get("limit"); limitStr != "" {
		val, err := strconv.Atoi(limitStr)
		if err != nil || val <= 0 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid limit query parameter"})
			return
		}
		if val > 500 {
			val = 500
		}
		limit = val
	}

	if h.puller == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "pull service unavailable"})
		return
	}

	req := &PullRequest{
		Since:          since,
		CatalogVersion: catalogVersion,
		Limit:          limit,
	}

	resp, err := h.puller.ProcessPull(r.Context(), req)
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
