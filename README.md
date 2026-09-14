# Rukun (Offline-First Mobile POS)

> **"Jualan terus, walau internet mati."**  
> **Versi Rilis:** `RILIS-2026.09.14`

Rukun adalah aplikasi Point of Sale (POS) mobile offline-first dengan arsitektur multi-terminal terdistribusi yang menyatu secara konsisten (*convergent*) saat kembali online tanpa duplikasi transaksi dan tanpa data hilang.

## Tech Stack

- **Mobile:** Flutter (FVM stable 3.47.4), Drift (SQLite), Riverpod, Anti-UI-Slop dark theme (`#16181C`)
- **Backend:** Go 1.27, Chi HTTP router, pgx/v5, Goose migrations, UUID v4
- **Database:** PostgreSQL 18 (Docker Compose)
- **Live Feed:** Server-Sent Events (SSE) + High-density Live Owner Console (HTML/CSS/JS)

## Struktur Monorepo

```
.
├── backend/                  # Go HTTP API, Event Store & SSE Hub
├── mobile/                   # Flutter offline-first cashier terminal
├── dashboard/                # Realtime live owner console (SSE)
├── docs/                     # PRD, specs, user guide, dan runbook
├── docker-compose.yml        # PostgreSQL service (port 5435)
└── .env.example              # Template variabel konfigurasi
```

## Prasyarat Lingkungan

- Go 1.27+
- FVM (Flutter Version Management) dengan Flutter SDK stable (3.47.4)
- Docker & Docker Compose

## Quick Start

### 1. Database

```bash
docker compose up -d
```

PostgreSQL berjalan di port `5435` dengan nama database `rukun_pos`.

### 2. Backend

```bash
cd backend
go run cmd/server/main.go
```

Backend berjalan di `http://localhost:8080`.

### 3. Mobile

```bash
cd mobile
fvm flutter pub get
fvm flutter run
```

### 4. Owner Live Dashboard

Buka file `dashboard/index.html` di browser untuk memantau transaksi secara real-time via SSE:

```bash
xdg-open dashboard/index.html
```

## Menjalankan Test Otomatis

```bash
# Test backend (Unit, Handlers, SSE Hub, dan E2E Multi-Terminal Convergence)
cd backend && go test -v -count=1 ./...

# Test mobile (Theme, Drift SQLite, Cart, Receipts, HLC Conflict, Sync Inspector)
cd mobile && fvm flutter analyze && fvm flutter test
```

## Dokumentasi Lengkap

- [End-User Guide (Panduan Kasir & Owner)](docs/END_USER_GUIDE.md)
- [Developer Runbook & Architecture](docs/DEVELOPER_RUNBOOK.md)
- [Sync Engine Architecture Spec](docs/superpowers/specs/2026-09-14-rukun-sync-engine-design.md)
- [PRD](docs/PRD.md)
- [Implementation Plan](docs/superpowers/plans/2026-09-14-rukun-implementation-plan.md)
