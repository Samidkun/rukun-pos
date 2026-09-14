package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/jackc/pgx/v5/pgxpool"
	"rukun.pos/backend/internal/store"
	syncengine "rukun.pos/backend/internal/sync"
)

func buildRouter(pool *pgxpool.Pool) *chi.Mux {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Device-ID"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok","app":"rukun_backend"}`))
	})

	pushService := syncengine.NewPushService(pool)
	pullService := syncengine.NewPullService(pool)
	syncHandler := syncengine.NewHandler(pushService, pullService)
	r.Post("/api/v1/sync/push", syncHandler.HandlePush)
	r.Get("/api/v1/sync/pull", syncHandler.HandlePull)

	return r
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}

	dbCtx, dbCancel := context.WithTimeout(context.Background(), 5*time.Second)
	pool, err := store.ConnectDB(dbCtx, store.DefaultConnStr())
	dbCancel()
	if err != nil {
		slog.Warn("PostgreSQL not reachable at startup, sync engine running in fallback mode", "error", err)
	} else {
		defer pool.Close()
		if err := store.RunMigrations(pool); err != nil {
			slog.Error("Failed to apply database migrations", "error", err)
		}
	}

	r := buildRouter(pool)

	server := &http.Server{
		Addr:         fmt.Sprintf(":%s", port),
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		slog.Info("Starting Rukun POS backend server", "port", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Server failed to listen", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	<-quit

	slog.Info("Shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		slog.Error("Server shutdown forced", "error", err)
	}
	slog.Info("Server exited gracefully")
}
