package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealthCheck(t *testing.T) {
	r := buildRouter(nil)

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	r.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	expectedBody := `{"status":"ok","app":"rukun_backend"}`
	if rec.Body.String() != expectedBody {
		t.Fatalf("expected body %q, got %q", expectedBody, rec.Body.String())
	}
}

func TestSyncPushRouteRegistered(t *testing.T) {
	r := buildRouter(nil)

	// Send an empty body to /api/v1/sync/push to verify the route is mounted and handled
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", strings.NewReader(`{}`))
	rec := httptest.NewRecorder()

	r.ServeHTTP(rec, req)

	// Route should be found, returning 400 Bad Request because the body is empty / invalid
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400 for empty push body on registered route, got %d: %s", rec.Code, rec.Body.String())
	}
}
