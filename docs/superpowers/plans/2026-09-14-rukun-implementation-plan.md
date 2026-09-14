# Rukun — Offline-First Mobile POS: Master Implementation Plan

> **Tracking:** Follows `superpowers:subagent-driven-development` and `superpowers:executing-plans`.
> **Spec Reference:** `docs/superpowers/specs/2026-09-14-rukun-sync-engine-design.md`
> **PRD Reference:** `docs/PRD.md`
> **Stack:** Flutter (FVM stable 3.47.4, Drift/SQLite, Riverpod) + Go 1.27 (Chi/Fiber, pgx/v5) + PostgreSQL 18 (Docker) + Dashboard Web (SSE feed).
> **Prinsip Eksekusi:** Vertikal tipis dulu (End-to-End event `sale` terkirim dan tersinkronisasi), baru melebar ke fitur lain. Anti-UI-slop `#16181C` dark theme.

---

## Phase 0 — Toolchain, Scaffolding & Monorepo Foundation

### Task 0.1: Monorepo Scaffolding & Environment Setup
**Files:**
- Create: `docker-compose.yml` (PostgreSQL 18 pada port `5435`, database `rukun_pos`, volume `.pgdata`)
- Create: `.env.example`
- Create: `.gitignore`
- Scaffold: `mobile/` via `fvm flutter create --org com.rukun.pos --project-name rukun_mobile mobile`
- Scaffold: `backend/` via `go mod init rukun.pos/backend`
- Create: `README.md`

- [x] **Step 1: Setup docker-compose.yml & local PostgreSQL**
- [x] **Step 2: Initialize Go module & essential dependencies** (`chi` / `fiber`, `pgx/v5`, `goose`, `google/uuid`)
- [x] **Step 3: Initialize Flutter mobile app with FVM stable**
- [x] **Step 4: Verify builds (`go build ./...` & `fvm flutter analyze`)**
- [x] **Step 5: Commit:** `chore: scaffold rukun monorepo with go backend and flutter mobile`

---

### Task 0.2: Design Tokens & Anti-UI-Slop Contract
**Files:**
- Create: `mobile/DESIGN.md` (Theme: Clean Dark `#16181C`, hairline border `#2A2E35`, accent `#C7F53B` electric lime / `#4EE5B6` serene mint, zero generic cards, zero emoji buttons)
- Create: `mobile/lib/core/theme/app_colors.dart`
- Create: `mobile/lib/core/theme/app_theme.dart`
- Test: `mobile/test/core/theme_test.dart`

- [x] **Step 1: Write mobile/DESIGN.md specification**
- [x] **Step 2: Implement AppColors & AppTheme in Flutter**
- [x] **Step 3: Verify and commit:** `feat(mobile): add design contract and core theme tokens`

---

## Phase 1 — Local POS (Offline Cashier & Struk)

### Task 1.1: Local Database Schema & Drift Setup
**Files:**
- Create: `mobile/lib/data/db/app_database.dart`
- Create: `mobile/lib/data/db/tables.dart` (Tabel: `products`, `sales`, `sale_items`, `stock_ledger`, `outbox_events`, `sync_state`)
- Test: `mobile/test/data/db_test.dart`

- [x] **Step 1: Define tables with drift/sqlite** (UUID primary keys, client_timestamp, synced_at)
- [x] **Step 2: Implement DAO for Products, Sales, and Outbox**
- [x] **Step 3: Write tests for local insertion & outbox generation**
- [x] **Step 4: Commit:** `feat(mobile): local drift database schema and outbox event tables`

---

### Task 1.2: Cashier Screen & Cart System (Hero Flow)
**Files:**
- Create: `mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Create: `mobile/lib/features/cashier/presentation/widgets/product_grid.dart`
- Create: `mobile/lib/features/cashier/presentation/widgets/cart_sheet.dart`
- Create: `mobile/lib/features/cashier/domain/cart_notifier.dart`
- Test: `mobile/test/features/cashier_flow_test.dart`

- [x] **Step 1: Product grid with instant search & stock badge**
- [x] **Step 2: Cart management (tambah, kurangi, hitung total)**
- [x] **Step 3: Checkout modal (cash / instant offline receipt)**
- [x] **Step 4: Atomic local transaction: Simpan `sale` + Simpan `outbox_events` + Potong local stock**
- [x] **Step 5: Commit:** `feat(mobile): offline cashier checkout flow with instant receipt preview`

---

### Task 1.3: Receipt Preview & Local Sales History
**Files:**
- Create: `mobile/lib/features/history/presentation/history_screen.dart`
- Create: `mobile/lib/features/history/presentation/receipt_preview_screen.dart`
- Test: `mobile/test/features/receipt_test.dart`

- [x] **Step 1: Screen list riwayat transaksi lokal (status: Pending Sync vs Synced)**
- [x] **Step 2: Struk preview format 58mm / 80mm monospaced clean**
- [x] **Step 3: Share struk via image/text**
- [x] **Step 4: Commit:** `feat(mobile): sales history and monospaced receipt preview`

---

## Phase 2 — Backend Sync Engine (Go + PostgreSQL)

### Task 2.1: Database Migrations & Event Store
**Files:**
- Create: `backend/migrations/00001_init_schema.sql`
- Tables: `devices`, `products`, `product_versions`, `sales`, `sale_items`, `stock_events`, `sync_events`
- Create: `backend/internal/store/db.go`
- Create: `backend/internal/store/events.go`
- Test: `backend/internal/store/events_test.go`

- [x] **Step 1: Goose migrations with append-only `sync_events` table**
- [x] **Step 2: Idempotency table & unique constraint on `(device_id, client_event_id)`**
- [x] **Step 3: Write tests for event insertion and duplicate drop**
- [x] **Step 4: Commit:** `feat(backend): postgresql event store and migrations with idempotency guards`

---

### Task 2.2: Push Endpoint (`/api/v1/sync/push`)
**Files:**
- Create: `backend/internal/sync/push_handler.go`
- Create: `backend/internal/sync/validator.go`
- Test: `backend/internal/sync/push_test.go`

- [x] **Step 1: Handle batch event push from mobile terminals**
- [x] **Step 2: Apply events transactionally to materialized tables (`sales`, `stock_events`)**
- [x] **Step 3: Return list of acknowledged event IDs**
- [x] **Step 4: Commit:** `feat(backend): batch sync push endpoint with transactional materialize`

---

### Task 2.3: Pull Endpoint (`/api/v1/sync/pull`)
**Files:**
- Create: `backend/internal/sync/pull_handler.go`
- Test: `backend/internal/sync/pull_test.go`

- [x] **Step 1: Return config & product updates since `last_server_version`**
- [x] **Step 2: Return global stock adjustment deltas**
- [x] **Step 3: Commit:** `feat(backend): delta sync pull endpoint with version cursor`

---

## Phase 3 — Client-Side Sync Worker & Conflict Resolution

### Task 3.1: Client Outbox Worker & Background Sync
**Files:**
- Create: `mobile/lib/data/sync/sync_worker.dart`
- Create: `mobile/lib/data/sync/sync_status_notifier.dart`
- Create: `mobile/lib/features/sync/presentation/sync_badge.dart`
- Test: `mobile/test/sync/sync_worker_test.dart`

- [x] **Step 1: Outbox loop: check connectivity -> push pending events -> mark synced**
- [x] **Step 2: Pull catalog updates -> update local Drift tables**
- [x] **Step 3: Visual Sync Badge: Green (Synced), Yellow (Pending N items), Red (Offline)**
- [x] **Step 4: Commit:** `feat(mobile): outbox background sync worker and live status badge`

---

### Task 3.2: Multi-Device Conflict & Stock Oversold Handling
**Files:**
- Create: `mobile/lib/data/sync/conflict_resolver.dart`
- Create: `mobile/lib/features/oversold/presentation/oversold_screen.dart`
- Test: `mobile/test/sync/conflict_test.dart`

- [x] **Step 1: Stock ledger: balance = SUM(inflow - outflow)**
- [x] **Step 2: Handle negative stock gracefully when 2 offline terminals sell the same item**
- [x] **Step 3: Product update LWW with Hybrid Logical Clock (HLC)**
- [x] **Step 4: Oversold audit screen for cashier & owner**
- [x] **Step 5: Commit:** `feat(mobile): conflict resolver with stock ledger and oversold alert`

---

### Task 3.3: Sync Inspector (Portfolio Showcase UI)
**Files:**
- Create: `mobile/lib/features/sync_inspector/presentation/sync_inspector_screen.dart`
- Test: `mobile/test/features/sync_inspector_test.dart`

- [x] **Step 1: Raw event viewer: inspect outbox queue, JSON payload, retry count**
- [x] **Step 2: Manual trigger: "Simulate Offline", "Force Push", "Corrupt Network Packet"**
- [x] **Step 3: Commit:** `feat(mobile): sync inspector debug screen for live interview demo`

---

## Phase 4 — Owner Live Dashboard (SSE & Web)

### Task 4.1: Server-Sent Events (SSE) Hub in Go
**Files:**
- Create: `backend/internal/realtime/sse_hub.go`
- Create: `backend/internal/realtime/handler.go`
- Test: `backend/internal/realtime/sse_test.go`

- [x] **Step 1: Broadcast newly synced transactions to connected owner clients via SSE**
- [x] **Step 2: Heartbeat & auto-reconnect handling**
- [x] **Step 3: Commit:** `feat(backend): real-time sse broadcast hub for owner dashboard`

---

### Task 4.2: Lightweight Owner Web Dashboard
**Files:**
- Create: `dashboard/index.html` (Vanilla / Vite high-density live feed)
- Create: `dashboard/app.js`
- Create: `dashboard/styles.css` (Dark theme matching mobile)
- Test: `backend/tests/e2e_live_feed_test.go`

- [x] **Step 1: Live feed of incoming transactions with device badge (`Kasir 1`, `Kasir 2`)**
- [x] **Step 2: Real-time revenue counter & top-selling items**
- [x] **Step 3: Oversold stock alert banner**
- [x] **Step 4: Commit:** `feat(dashboard): live owner sales feed and real-time revenue stats`

---

## Phase 5 — Multi-Terminal Verification & Documentation

### Task 5.1: Multi-Terminal Convergence Test (Simulated E2E)
**Files:**
- Create: `tests/e2e/multi_terminal_sync_test.go`

- [x] **Step 1: Test Scenario: Terminal A & B sell same product while offline**
- [x] **Step 2: Both reconnect simultaneously -> verify zero duplicates, correct total revenue, stock negative detected**
- [x] **Step 3: Commit:** `test(e2e): multi-terminal simultaneous offline-to-online convergence test`

---

### Task 5.2: Dual-Audience Documentation (RILIS-2026.09.14)
**Files:**
- Create: `docs/END_USER_GUIDE.md` (Panduan kasir & owner saat internet mati)
- Create: `docs/DEVELOPER_RUNBOOK.md` (Arsitektur sync engine, skema HLC, cara menjalankan multi-device demo)
- Update: `README.md`

- [ ] **Step 1: Write END_USER_GUIDE.md**
- [ ] **Step 2: Write DEVELOPER_RUNBOOK.md**
- [ ] **Step 3: Commit:** `docs: add end-user guide, developer runbook, and portfolio demo guide`

---
