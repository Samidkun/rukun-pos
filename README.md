# Rukun (Offline-First Mobile POS)

> **"Jualan terus, walau internet mati."**

Rukun adalah aplikasi Point of Sale (POS) mobile offline-first dengan arsitektur multi-terminal yang menyatu secara konsisten (*convergent*) saat kembali online tanpa duplikasi transaksi dan tanpa data hilang.

## Tech Stack

- **Mobile:** Flutter (FVM stable 3.47.4), Drift (SQLite), Riverpod
- **Backend:** Go 1.27, Chi HTTP router, pgx/v5, Goose migrations
- **Database:** PostgreSQL 18 (Docker Compose)
- **Live Feed:** Server-Sent Events (SSE) + Lightweight Vanilla Dashboard

## Struktur Monorepo

```
.
├── backend/                  # Go HTTP API & Sync Engine
├── mobile/                   # Flutter offline-first cashier terminal
├── dashboard/                # Realtime live web dashboard (SSE)
├── docs/                     # PRD, specs, dan user guide / runbook
├── docker-compose.yml        # PostgreSQL service (port 5435)
└── .env.example              # Template variabel konfigurasi
```

## Prasyarat Lingkungan

- Go 1.27+
- FVM (Flutter Version Management) dengan Flutter SDK stable
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

## Dokumen Desain & Rencana

- [PRD](docs/PRD.md)
- [Sync Engine Architecture Spec](docs/superpowers/specs/2026-09-14-rukun-sync-engine-design.md)
- [Implementation Plan](docs/superpowers/plans/2026-09-14-rukun-implementation-plan.md)
