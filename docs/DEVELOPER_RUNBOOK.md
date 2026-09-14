# Developer Architecture & Runbook — Rukun POS Sync Engine

> **Versi Rilis:** `RILIS-2026.09.14`  
> **Klasifikasi:** Distributed Systems, Event-Sourcing, Offline-First Mobile

---

## 1. Arsitektur Inti

### 1.1 Ownership Partitioning
- **Penjualan (Sales):** Milik terminal kasir (device-authoritative). Bersifat *append-only*, hanya naik ke server. Menghilangkan race condition penulisan.
- **Konfigurasi (Products & Prices):** Dominan milik server (server-authoritative), terminal hanya meniru dan boleh menyarankan perubahan (LWW per-field).

### 1.2 Stok sebagai Derived Ledger
Stok tidak pernah di-overwrite secara atomik dengan nilai mutlak. Setiap mutasi stok dicatat sebagai delta bertanda (`+N` restock, `-N` penjualan):
```
Current Stock = base_stock + Σ(stock_movements.delta)
```
Karena operasi penjumlahan bersifat komutatif dan asosiatif, event yang datang tidak berurutan dari berbagai terminal akan selalu menghasilkan state stok yang identik (*strong eventual convergence*).

### 1.3 Hybrid Logical Clock (HLC)
Mengatasi *clock drift* pada HP Android/iOS kasir:
```
HLC format: "<physical_ms>-<logical_counter>-<device_id>"
```
Perbandingan deterministik:
1. `physical_ms` (epoch milliseconds)
2. `logical_counter` (increment jika physical time sama)
3. `device_id` (tie-breaker leksikografis deterministik)

---

## 2. Struktur Monorepo

```
.
├── backend/                       # Go 1.27 + Chi + pgx/v5
│   ├── cmd/server/main.go         # HTTP Server & Router
│   ├── internal/store/            # PostgreSQL Connection & Event Store
│   ├── internal/sync/             # /push and /pull Handlers & Validators
│   ├── internal/realtime/         # Server-Sent Events (SSE) Broadcast Hub
│   ├── migrations/                # Goose SQL Migrations (PostgreSQL)
│   └── tests/                     # Integration & E2E Tests
├── mobile/                        # Flutter (FVM stable 3.47.4)
│   ├── lib/core/theme/            # Anti-UI-Slop Clean Dark Theme (#16181C)
│   ├── lib/data/db/               # Drift SQLite local tables & DAOs
│   ├── lib/data/sync/             # SyncWorker, HLC, ConflictResolver
│   ├── lib/features/cashier/      # Product Grid & Cart Riverpod Notifier
│   ├── lib/features/history/      # Monospaced Thermal Receipt Preview (58mm/80mm)
│   ├── lib/features/oversold/     # C1 Oversold Audit Screen
│   └── lib/features/sync_inspector/ # Live Interview Demo & Debug Console
├── dashboard/                     # Real-time Live Owner Dashboard (SSE)
│   ├── index.html
│   ├── app.js
│   └── styles.css
├── docs/                          # PRD, Specs, User Guide, Runbook
└── docker-compose.yml             # PostgreSQL 18 on Port 5435
```

---

## 3. Menjalankan Portfolio Live Demo (Untuk Interview Kerja)

Demo ini dirancang untuk menunjukkan kebenaran sinkronisasi terdistribusi di depan recruiter atau interviewer teknis.

### Langkah 1: Jalankan Database & Backend
```bash
# Di terminal 1: Nyalakan PostgreSQL
docker compose up -d

# Di terminal 2: Jalankan backend Go
cd backend
go run cmd/server/main.go
```
Backend akan aktif di `http://localhost:8080`.

### Langkah 2: Buka Dashboard Owner
Buka file `dashboard/index.html` di browser (misal Chrome):
```bash
xdg-open dashboard/index.html || open dashboard/index.html
```
Status pill di kanan atas akan menampilkan **"LIVE STREAMING"** (terhubung ke SSE `/api/v1/realtime/sales`).

### Langkah 3: Jalankan Mobile Terminal
```bash
cd mobile
fvm flutter run -d linux
```

### Langkah 4: Skenario Demo Offline-to-Online
1. Pada aplikasi mobile kasir, tekan **Sync Badge** di kanan atas untuk membuka **Sync Inspector**.
2. Aktifkan sakelar **"Simulasi Mode Offline"**.
3. Kembali ke kasir, tambahkan 2 cangkir kopi, lalu tekan **Bayar**.
   - Transaksi langsung berhasil dibuat secara offline.
   - Nomor struk urut gapless: `T01-000001`.
   - Badge menunjukkan `"1 Tertunda"`.
4. Buka kembali **Sync Inspector**: perhatikan antrean outbox berisi event JSON mentah yang belum terkirim.
5. Matikan sakelar **"Simulasi Mode Offline"**, lalu tekan **"Force Sync Sekarang"**.
6. **Hasil:**
   - Badge mobile langsung berubah menjadi hijau **"Tersinkron"**.
   - Di browser dashboard owner, transaksi `T01-000001` langsung muncul seketika (*zero delay*) dengan efek pulsasi halus dan total omzet langsung bertambah.

---

## 4. Menjalankan Pengujian Otomatis

### Backend Go Suite:
```bash
cd backend
go test -v -count=1 ./...
```
Mencakup:
- Unit validation push envelope & JSON payload
- HTTP push handler & transactional materialization
- Delta pull handler & catalog versioning
- SSE Hub streaming & heartbeat tests
- E2E multi-terminal concurrent push convergence test

### Mobile Flutter Suite:
```bash
cd mobile
fvm flutter analyze
fvm flutter test
```
Mencakup:
- Design tokens & anti-UI-slop theme tests
- Drift SQLite schema & stock ledger calculation tests
- CartNotifier Riverpod unit tests & Cashier screen widget tests
- Monospaced receipt format & history preview tests
- HLC ordering & C1 oversold detection tests
- SyncInspector widget tests
