package store

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"rukun.pos/backend/migrations"
)

// Store wraps database connection pool and exposes data operations.
type Store struct {
	Pool *pgxpool.Pool
}

// NewStore instantiates a Store backed by the given pgx connection pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool}
}

// DefaultConnStr returns DATABASE_URL or the local development default.
// ponytail: hardcoded fallback dsn; upgrade to structured config when adding multi-env deployment.
func DefaultConnStr() string {
	if connStr := os.Getenv("DATABASE_URL"); connStr != "" {
		return connStr
	}
	return "postgres://postgres:postgres@localhost:5432/rukun?sslmode=disable"
}

// ConnectDB establishes a connection pool to PostgreSQL.
func ConnectDB(ctx context.Context, connStr string) (*pgxpool.Pool, error) {
	if connStr == "" {
		connStr = DefaultConnStr()
	}

	config, err := pgxpool.ParseConfig(connStr)
	if err != nil {
		return nil, fmt.Errorf("parse db config: %w", err)
	}

	config.MaxConns = 25
	config.MinConns = 2
	config.MaxConnIdleTime = 5 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("connect db pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping db: %w", err)
	}

	return pool, nil
}

// RunMigrations applies all pending Goose migrations using the connection pool.
func RunMigrations(pool *pgxpool.Pool) error {
	sqlDB := stdlib.OpenDBFromPool(pool)
	defer sqlDB.Close()

	return RunMigrationsWithDB(sqlDB)
}

// RunMigrationsWithDB applies all pending Goose migrations against a *sql.DB handle.
func RunMigrationsWithDB(db *sql.DB) error {
	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		return fmt.Errorf("set goose dialect: %w", err)
	}
	if err := goose.Up(db, "."); err != nil {
		return fmt.Errorf("apply goose migrations: %w", err)
	}
	return nil
}

// RunMigrationsURL applies all Goose migrations given a connection string.
func RunMigrationsURL(connStr string) error {
	if connStr == "" {
		connStr = DefaultConnStr()
	}
	db, err := sql.Open("pgx", connStr)
	if err != nil {
		return fmt.Errorf("open sql db for migrations: %w", err)
	}
	defer db.Close()
	return RunMigrationsWithDB(db)
}
