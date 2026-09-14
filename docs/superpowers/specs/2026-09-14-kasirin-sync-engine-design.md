# Kasirin — Offline-First Mobile POS: Design Spec

> **Status:** Approved (design phase) · **Tanggal:** 2026-09-14 · **Pemilik:** Samid
> **Klasifikasi:** Architectural (project baru) · **Sumber proses:** `superpowers:brainstorming`
> **Tujuan:** Flagship portofolio untuk melamar kerja (posisi fullstack).

---

## 1. Ringkasan Eksekutif

**Kasirin** adalah aplikasi kasir (POS) mobile **offline-first**: kasir bisa bertransaksi penuh tanpa internet, dan data menyatu otomatis saat koneksi kembali — aman untuk **multi-device** (2+ HP kasir + 1 dashboard owner), tanpa duplikasi dan tanpa kehilangan data.

Yang membuat project ini bernilai portofolio bukan fitur kasirnya, melainkan **model sinkronisasinya**. Pendekatan yang dipilih **bukan** CRDT penuh (overkill & salah sasaran untuk POS), melainkan kombinasi yang sudah terbukti di POS produksi:

> **Partisi kepemilikan** (penjualan naik, konfigurasi turun) + **append-only event log** + **stok sebagai ledger** + **konflik diselesaikan sebagai keputusan bisnis eksplisit**.

Tagline: **"Jualan terus, walau internet mati."**

---

## 2. Masalah & Tujuan

### 2.1 Masalah
Warung/kafe/toko di Indonesia sering internetnya mati/tidak stabil, sering punya **lebih dari satu kasir/HP**, dan aplikasi POS online-only **berhenti total** saat internet putus. Aplikasi offline-first yang benar biasanya mahal atau tertutup.

Masalah intinya adalah **masalah sistem terdistribusi**:
> Bagaimana membuat POS yang bisa transaksi penuh tanpa internet, di banyak device sekaligus, lalu **menyatu otomatis (converge)** tanpa data dobel, hilang, atau konflik?

### 2.2 Goals
1. Transaksi kasir 100% jalan tanpa internet.
2. Data lokal persisten (selamat saat app ditutup / HP restart).
3. Sync otomatis saat online (tanpa tombol manual).
4. Multi-device converge ke state identik.
5. Retry sync tidak menghasilkan duplikasi.
6. Owner bisa lihat penjualan live saat kasir online.

### 2.3 Non-Goals (YAGNI — sengaja TIDAK dibangun)
- Payment gateway / EDC / QRIS real.
- Multi-tenant + billing/langganan.
- Modul akuntansi, hutang-piutang, pembelian supplier.
- Manajemen karyawan/shift.
- Cetak printer thermal fisik (cukup preview struk + share PDF).
- Skala produksi (jutaan user). Fokus: **kebenaran sync engine**.

> **Prinsip scope:** lebih baik 1 sync engine yang benar dan bisa didemokan daripada 10 fitur setengah jadi.

---

## 3. Keputusan Arsitektur Inti

### 3.1 Prinsip #1 — Partisi Kepemilikan (Ownership Partition)

Dua aliran data yang **tidak pernah menulis baris yang sama**:

| Aliran | Pemilik | Arah | Konflik |
|---|---|---|---|
| **Config** (produk, harga, kategori, user) | **Server-authoritative**, tapi terminal **boleh mengedit** (mis. ubah harga di device) | **bidirectional** | ⚠️ jarang → **LWW per-field** |
| **Sales** (penjualan, gerakan stok) | **Terminal** | naik ke atas (append-only) | ❌ tidak ada |

Karena penjualan hanya naik dan konfigurasi turun secara dominan, keduanya **jarang rebutan baris** → sebagian besar konflik hilang *by design*, bukan diselesaikan dengan mekanisme merge yang rumit. Satu-satunya entity yang benar-benar **bidirectional** adalah **produk** (server push katalog; terminal boleh push edit harga/nama) — dan itu diselesaikan deterministik via HLC + LWW per-field (§6.2).

### 3.2 Prinsip #2 — Sales Append-Only, Stok Derived

Penjualan bersifat **immutable** (fakta yang sudah terjadi, bukan permintaan izin). Stok **tidak disimpan** sebagai kolom yang di-*overwrite*, melainkan **diturunkan** dari ledger gerakan stok:

```
stok(product) = base_stock + Σ(delta dari semua stock_movements)
```

Penjumlahan bersifat **komutatif & asosiatif** → urutan event tidak penting, hasil selalu sama (bebas race condition dua kasir).

### 3.3 Prinsip #3 — Konflik = Keputusan Bisnis, bukan Default Teknis

> Konflik adalah masalah bisnis yang disamarkan menjadi masalah teknis.

Mekanisme teknis (HLC/LWW) hanya dipakai untuk **satu** jenis konflik (edit produk). Sisanya diselesaikan dengan aturan bisnis eksplisit.

### 3.4 Prinsip #4 — Setiap Perubahan = Event (Outbox)

Setiap tulis ke tabel state **WAJIB** disertai insert ke `outbox` **dalam satu transaksi DB yang sama** → mustahil ada perubahan tanpa jejak event.

### 3.5 Alternatif yang Ditolak (dan alasannya)

| Pendekatan | Kenapa ditolak |
|---|---|
| **CRDT penuh (RGA/OT)** | POS tidak butuh causal ordering teks. Overkill; masalah aslinya (overselling, harga berubah) adalah masalah bisnis, bukan matematika. |
| **Server-authoritative** | Bukan offline-first sejati (device jadi lemah). Paling lemah untuk portofolio. |
| **LWW per-baris** | Kalau device A ubah harga & device B ubah nama bersamaan, salah satu edit hilang. Dipakai LWW **per-field** sebagai gantinya. |
| **Vector clock** | HLC sudah cukup dan lebih sederhana. |

---

## 4. Model Data

### 4.1 Aturan Wajib (field-proven — jangan dilanggar)

| # | Aturan | Alasan |
|---|---|---|
| 1 | **PK selalu UUID v4 dibuat di device.** Haram auto-increment integer lokal. | Dua terminal mulai dari ID 1 → tabrakan saat sync |
| 2 | **Uang = integer unit terkecil** (`price_cents`), bukan float | Float duit = salah hitung, laporan tidak balance |
| 3 | **SQLite WAL mode** + transaksi eksplisit tiap write | Terminal mati saat nulis (listrik padam) → DB tidak korup |
| 4 | **Status sync per-record, bukan per-batch** | Server terima 90/100 → tandai batch "synced" = kehilangan 10 data diam-diam |
| 5 | **Setiap perubahan = event di outbox, transaksi sama** | Mustahil ada perubahan tanpa jejak |

### 4.2 Skema Lokal (Flutter / Drift)

```sql
PRAGMA journal_mode = WAL;

-- CONFIG (milik server; terminal cuma niru)
products (
  id TEXT PRIMARY KEY, name TEXT, category TEXT,
  price_cents INTEGER, base_stock INTEGER,
  updated_hlc TEXT, deleted INTEGER DEFAULT 0, catalog_version INTEGER
);

-- SALES (milik terminal; naik ke atas)
sales (
  id TEXT PRIMARY KEY,                 -- UUID v4 dibuat di device
  invoice_series TEXT, invoice_number INTEGER,   -- counter lokal, gapless
  terminal_id TEXT, total_cents INTEGER, payment_method TEXT,
  occurred_at INTEGER, synced_at INTEGER         -- NULL = belum ke-upload
);
sale_items (
  id TEXT PRIMARY KEY, sale_id TEXT, product_id TEXT,
  name TEXT, price_cents INTEGER,      -- SNAPSHOT nama & harga saat transaksi
  qty INTEGER
);

-- STOK: LEDGER, bukan angka yang di-overwrite
stock_movements (
  id TEXT PRIMARY KEY, product_id TEXT, delta INTEGER,   -- bertanda: -2 jual, +5 restock
  reason TEXT,                          -- sale|return|purchase|adjust|wastage
  sale_id TEXT, hlc TEXT, synced_at INTEGER
);

-- OUTBOX + STATE SYNC
outbox (
  event_id TEXT PRIMARY KEY,            -- = idempotency key
  entity_type TEXT, entity_id TEXT, op TEXT, payload TEXT, hlc TEXT,
  status TEXT,                          -- pending|inflight|done|rejected
  attempt INTEGER DEFAULT 0, created_at INTEGER
);
sync_state (key TEXT PRIMARY KEY, value TEXT);
  -- last_pulled_seq | catalog_version | device_id | invoice_counter
```

**Catatan penting:** `sale_items` menyimpan **snapshot** `name` & `price_cents`. Jadi kalau produk di-rename/re-price belakangan, struk lama **tidak berubah**. Ini aturan bisnis nyata: *jualan yang belum ke-sync tidak pernah di-reprice mundur* — supaya laporan Z akhir hari cocok dengan uang di laci.

### 4.3 Nomor Struk — Seri per-Terminal

```
terminal T01 → T01-000001, T01-000002, ...   (counter lokal, gapless, selalu bisa offline)
terminal T02 → T02-000001, ...
UNIQUE (terminal_id, invoice_series, invoice_number)
```

Menghindari jebakan paling mahal: nomor urut global butuh server → butuh internet → offline buyar. Solusi lapangan: tiap terminal punya serinya sendiri.

### 4.4 Skema Server (PostgreSQL 16)

```sql
events (server_seq BIGSERIAL PK,        -- urutan global, jadi kursor pull
        event_id TEXT UNIQUE,           -- dedupe idempotency
        terminal_id TEXT, device_id TEXT,
        entity_type TEXT, entity_id TEXT, op TEXT,
        payload JSONB, hlc TEXT,
        status TEXT DEFAULT 'applied',  -- applied|rejected
        reject_reason TEXT,
        received_at TIMESTAMPTZ DEFAULT now());

products     (id TEXT PK, name TEXT, category TEXT, price_cents INT,
              updated_hlc TEXT, deleted BOOL, catalog_version INT);
sales        (id TEXT PK, invoice_series TEXT, invoice_number INT,
              terminal_id TEXT, total_cents INT, payment_method TEXT,
              occurred_at TIMESTAMPTZ, received_at TIMESTAMPTZ DEFAULT now(),
              UNIQUE(terminal_id, invoice_series, invoice_number));
sale_items   (id TEXT PK, sale_id TEXT, product_id TEXT, name TEXT,
              price_cents INT, qty INT);
stock_movements (id TEXT PK, product_id TEXT, delta INT, reason TEXT,
              sale_id TEXT, hlc TEXT);
catalog_version (id INT PK DEFAULT 1, version INT, updated_at TIMESTAMPTZ);
devices      (device_id TEXT PK, terminal_id TEXT, last_seen_seq BIGINT);
```

---

## 5. Protokol Sync

### 5.1 PUSH (terminal → server)

```
POST /api/v1/sync/push
{ "terminal_id": "T01", "device_id": "d-a1",
  "events": [
    { "event_id": "e-7f3c...", "entity_type": "sale", "op": "create",
      "hlc": "1766000000123-0-d-a1",
      "payload": { "invoice_series": "T01", "invoice_number": 47,
                   "total_cents": 25000, "items": [ ... ] } }
  ] }

→ { "accepted": ["e-7f3c..."],
    "rejected": [{ "event_id": "e-9a", "reason": "unknown_product" }],
    "server_seq_max": 1042,
    "catalog_version": 88 }
```

**Proses server (per event, dalam 1 transaksi):**
```sql
INSERT INTO events (event_id, terminal_id, device_id, entity_type, entity_id, op, payload, hlc)
VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
ON CONFLICT (event_id) DO NOTHING;   -- retry 100x tetap 1 transaksi
-- jika insert lolos → apply ke tabel materialized, status 'applied'
-- jika rejected → SIMPAN alasannya (status 'rejected'), jangan dibuang diam-diam
```

### 5.2 PULL (server → terminal)

```
GET /api/v1/sync/pull?since=1042&catalog_version=87

→ { "events": [ ... event dari terminal lain ... ],
    "catalog": null,            // atau full diff jika catalog_version ketinggalan
    "next_since": 1542, "has_more": false }
```

Client: skip event dengan `device_id` sendiri → apply sisanya → simpan `next_since`. Kursor `server_seq` (BIGSERIAL) monoton → pull tahan-putus & tidak pernah kehilangan event.

### 5.3 Loop Sync (client)

```
tiap 5 detik | app resume | koneksi kembali:
  1. outbox 'pending'? → push batch ≤200, tandai per-record
  2. pull sampai has_more = false
  3. catalog_version ketinggalan? → download diff → apply ATOMIK
     (BEGIN; hapus katalog lama; insert baru; COMMIT — mati di tengah = aman)
  4. gagal? → exponential backoff 1s→2s→4s→8s, maks 60s
```

Push **selalu** sebelum pull.

---

## 6. Penanganan Konflik

### 6.1 Tiga Jenis Konflik (hanya tiga)

| # | Konflik | Penyebab | Penyelesaian |
|---|---|---|---|
| **C1** | Dua terminal jual unit terakhir bersamaan | Keduanya tak tahu jualan satu sama lain | **Aturan bisnis** (§6.3) |
| **C2** | Harga diubah server saat ada jualan pending | Katalog turun, jualan naik | **Snapshot** (§4.2) — sudah beres |
| **C3** | Dua device edit produk bersamaan | Terminal bisa juga edit produk | **HLC + LWW per-field** (§6.2) |

Hanya **C3** yang butuh mekanisme merge teknis.

### 6.2 C3 — HLC + LWW per-field

**Hybrid Logical Clock:** `hlc = "<physical_ms>-<logical>-<device_id>"` — monotonik walau jam device meleset; bisa dibandingkan total (tie-break `device_id`) → **deterministik**.

```
apply(product.update):
  untuk tiap field di payload:
     jika incoming.hlc > field.updated_hlc:
        field.value = incoming.value
        field.updated_hlc = incoming.hlc
```

**LWW per-field, bukan per-baris:** device A ubah *harga*, device B ubah *nama* → keduanya selamat. Per-baris akan menghilangkan salah satunya.

### 6.3 C1 — Dua Terminal Jual Unit Terakhir (Overselling)

Stok = 1. T01 (offline) jual 1. T02 (offline) jual 1. Sync → total jual 2, stok −1. **Aturan bisnis eksplisit:**

1. **Jualan tetap tercatat apa adanya.** Dua-duanya nyata; pelanggan sudah bawa barang. Tidak boleh dihapus.
2. **Stok boleh minus** — itu **sinyal yang benar**, bukan error. Minus = "perlu diurus", bukan "data rusak".
3. Sistem menandai `OVERSOLD` → masuk **daftar tindak lanjut** di dashboard owner: *"SKU-X oversold 1 unit"*.
4. Owner memilih: restock cepat / refund salah satu / backorder.

> Saat offline, *locking* untuk mencegah overselling **mustahil** (tak ada koordinator). Jawaban jujurnya bukan "cegah", tapi **"deteksi & tangani dengan rapi"**.

### 6.4 Yang Sengaja Tidak Dibuat (YAGNI)

| Tidak dibuat | Alasan |
|---|---|
| CRDT penuh (RGA/OT) | POS tidak butuh causal ordering teks |
| Vector clock | HLC cukup, lebih simpel |
| Auto-merge stok | Overselling = keputusan bisnis, bukan matematika |
| Konflik-resolusi real-time antar terminal | Server jadi titik temu; terminal lain tidak perlu tahu langsung |

---

## 7. UI/UX & Kontrak Desain

Konteks pemakaian: **buru-buru, pakai jempol, kadang internet mati.** Vibe: *"mesin kasir, bukan landing page."* Kontrak lengkap ditulis sebagai `DESIGN.md` (mobile & dashboard).

### 7.1 Tokens (satu sumber: `lib/theme.dart`, hardcoded)

```
bg         #15171B   (BUKAN #000 — #000 = slop)
surface    #1D2026   card; hairline #292D34 1px
text       #F2F3F5 / muted #98A0AC / faint #5E646E
accent     #FFB020   (amber kasir — hangat, kontras tinggi;
                      bukan biru korporat generik, bukan hijau "money" klise)
ok #4ADE80 · pending #FBBF24 · danger #F87171   (HANYA status sync & oversold)
font       angka = monospace (JetBrains Mono/Roboto Mono) untuk harga/qty/stok
           teks = system default; display 28/w700, title 18/w600, body 14, caption 12
radius 10 · spacing base 8 (8/16/24) · kontrol min 48dp
```

### 7.2 Aturan Layout

- **Layar Kasir = HERO.** Grid produk 2 kolom, search satu bar di atas, keranjang = bottom sheet.
- **Angka leading.** Harga & total monospace besar. Hierarchy dari **TYPE**, bukan shadow/gradient.
- **Badge sync = elemen tetap di app bar**: `● Online` / `○ Offline` / `↑ 5 menunggu` / `✓ Tersinkron`.
- **Item keranjang = baris compact** (nama — 2× — Rp25.000), swipe untuk hapus.
- **Struk = preview bersih** (monospace, separator putus-putus) + tombol share PDF.
- **Sync Inspector** = halaman debug: event mentah + status + `server_seq` (monospace, ndjson-style).
- **Oversold alert** muncul di dashboard owner (tidak disembunyikan).

### 7.3 DILARANG (auto-reject saat review)

1. Emoji di tombol/judul; ikon pakai **Material Symbols**, satu stroke weight.
2. Gradient hero, glassmorphism, shadow blur >16, card bertingkat.
3. Copy marketing ("Kelola bisnismu lebih mudah!"). Label fungsional saja.
4. Bottom nav >4 tab; sidebar di phone.
5. Spinner full-page kecuali start app; tombol async = disabled + progress inline.
6. **Semua state wajib ada**: empty / loading / error(retry) / offline-banner / sync-pending-banner. Offline = **banner atas, bukan dialog**.
7. Dark saja; **tidak ada light mode** (scope). Toggle = slop.
8. Menyembunyikan status sync. Kasir harus **selalu** tahu "data gw aman belum?".

### 7.4 Review Gate (sebelum merge task UI)

Checklist §7.3 (1–8) + `fvm flutter analyze` clean + jalankan di emulator/Linux desktop & **lihat sendiri 1×**.

---

## 8. Testing

Sync adalah kode yang **gagal diam-diam** — testing bukan tempelan, tapi inti.

| Level | Yang diuji | Alat |
|---|---|---|
| Unit (Dart) | Urutan HLC; merge LWW per-field; hitung stok dari ledger | `test` |
| Unit (Go) | Dedupe `event_id`; ordering `server_seq`; apply per-record | `go test` |
| **Property test** ⭐ | **Set event dalam urutan ACAK → hasil wajib identik** | Dart + Go |
| Integration | 2 client: offline → push bareng → converge; retry 100× → 0 duplikat | Docker + Postgres |
| E2E | Mode pesawat → jualan → online → sync | Playwright/integration |

**Property test adalah senjata utama:** bukti bahwa konvergensi benar, bukan sekadar klaim.

---

## 9. Deliverables

- [ ] `docs/PRD.md` — masalah, persona, MoSCoW, non-goals
- [ ] `docs/USER_MANUAL.md` — untuk kasir & owner (non-teknis)
- [ ] `docs/DEVELOPER_RUNBOOK.md` — untuk dev: cara jalanin, arsitektur, troubleshooting sync
- [ ] `docs/superpowers/specs/2026-09-14-kasirin-sync-engine-design.md` — spec ini
- [ ] `docs/superpowers/plans/...` — implementation plan (dari writing-plans)
- [ ] `mobile/DESIGN.md` + `dashboard/DESIGN.md` — kontrak anti-slop
- [ ] `README.md` — masalah→solusi, diagram, GIF/video, cara jalanin
- [ ] Video demo ≤90 detik
- [ ] E2E test suite hijau
- [ ] Repo publik, riwayat commit rapi

---

## 10. Struktur Repo (monorepo)

```
kasirin/
├── mobile/                      # Flutter (kasir)
│   ├── lib/
│   │   ├── data/
│   │   │   ├── db/              # Drift: tabel, DAO, migrasi
│   │   │   └── sync/            # outbox, sync worker, HLC, conflict resolver
│   │   ├── features/
│   │   │   ├── cashier/         # layar kasir (HERO)
│   │   │   ├── products/
│   │   │   ├── history/         # riwayat + preview struk
│   │   │   ├── sync_inspector/  # debug & bukti event mentah
│   │   │   └── oversold/        # tindak lanjut stok minus
│   │   ├── theme.dart
│   │   └── main.dart
│   ├── DESIGN.md
│   └── test/sync/
├── backend/                     # Go (Fiber)
│   ├── cmd/server/main.go
│   ├── internal/
│   │   ├── sync/                # handler push/pull, dedupe, ordering
│   │   ├── store/               # pgx: events, ledger, materialized apply
│   │   ├── catalog/             # versioning katalog
│   │   └── realtime/            # SSE hub
│   ├── migrations/
│   └── go.mod
├── dashboard/                   # Next.js owner (read-only + SSE)
│   └── DESIGN.md
├── docker-compose.yml
├── .github/workflows/ci.yml
└── README.md
```

---

## 11. Roadmap Milestone

| MS | Isi | Target |
|---|---|---|
| **M0** | Repo, docker-compose, skeleton Go+Flutter, CI | fondasi |
| **M1** | POS lokal (Flutter+Drift): produk, kasir, struk — belum sync | "bisa jualan" |
| **M2** | Backend Go: `/sync/push` & `/pull`, idempotency, event log | "backend hidup" |
| **M3** | Sync engine client: outbox, worker, badge, Sync Inspector | "beneran sync" |
| **M4** | Konflik: HLC+LWW per-field, ledger stok, seri struk, oversold | "tahan 2 device" |
| **M5** | Dashboard owner: feed live SSE, grafik, alert oversold | "kelihatan produk" |
| **M6** | Polish, docs lengkap, rekam video demo | "siap dipajang" |

**Prinsip urutan:** bangun **vertikal tipis dulu** (entity `sale` end-to-end: Drift→outbox→push→log→pull→tampil), baru melebar.

---

## 12. Definisi Selesai (v1)

- [ ] Semua fitur Must-Have jalan
- [ ] Skenario video demo bisa direkam **sekali jalan tanpa edit**
- [ ] 2 device terbukti converge + anti-duplikat (property test hijau)
- [ ] Docs dual-audience lengkap + DESIGN.md dipatuhi
- [ ] `README.md` "jual" + video + repo rapi

---

## 13. Riset & Sumber (grounding)

Desain ini di-grounding pada pengalaman praktisi yang membangun POS offline-first produksi, bukan asumsi. Sumber utama:

1. **Sandeep Kushwaha** — *"Building a POS system that keeps selling when the internet drops"*
   https://sandeepkushwaha.com.np/blog/offline-first-point-of-sale-architecture
   → Sumber untuk: **partisi kepemilikan** ("each terminal is authoritative for the sales it rings up; the server is authoritative for everything shared"), **sales append-only / stock derived**, **seri invoice per-terminal**, UUID di device, uang sebagai integer minor unit.

2. **Voxire** — *"Building Offline-First POS Systems in Go with SQLite"*
   https://voxire.com/blog/offline-first-pos-go-sqlite-sync/
   → Sumber untuk: SQLite **WAL mode** + transaksi eksplisit, **local_id sebagai idempotency key**, **status sync per-record bukan per-batch**, catalog update **atomik**, dan prinsip **"resolution rule must be an explicit business decision, not a technical default"**.

3. **BC4** — *"How to Run Retail Point of Sale Platforms Offline and Sync Sales Later"*
   https://bc4.com/blog/running-retail-pos-offline-and-syncing-sales-later
   → Sumber untuk: skenario **dua terminal jual unit terakhir offline** dan bahwa rekonsiliasi stok adalah keputusan yang harus dibuat eksplisit; pentingnya terminal punya salinan katalog terkini sebelum offline.

4. **Derrick S. K. Siawor (DerkOnline)** — *"Design Offline-First Mobile Sync That Survives Bad Networks"*
   https://derkonline.com/blog/offline-first-mobile-sync-conflicts
   → Sumber untuk: **local-first / optimistic update**, **durable mutation queue** (survive app kill), delta sync, dan framing **LWW vs CRDT**.

5. **Muhammad Abdu Ar Rahman** — *"Mastering Mobile Offline Sync: Beyond the Basic Cache"*
   https://abduarrahman.com/blog/mastering-mobile-offline-sync/
   → Sumber untuk: pola **Outbox**, **Tombstone** (soft-delete), dan Queue→Push→Pull→Merge.

6. **"You Might Not Need a CRDT"** (diskusi, 372 poin HN)
   https://news.ycombinator.com/item?id=33865672
   → Sumber untuk: alasan **menolak CRDT penuh** sebagai overkill untuk kasus POS.

7. **Offline-first POS — event streams & merging divergent terminals** (DEV Community)
   https://dev.to/jam-techcirkle/offline-first-pos-event-streams-client-ids-and-merging-divergent-terminals-g5k
   → Konteks tambahan: apa yang hidup lokal, cara identifier bekerja, operasi yang memang tidak bisa di-merge.

8. **ChannelDock** — *"How to recover POS offline sales and sync inventory"*
   https://channeldock.com/en/how-to-recover-pos-offline-sales-sync
   → Konteks tambahan: pola recovery **buffer → replay → match → release**.

9. **Loyverse** — *"Offline Use of Loyverse POS"* (referensi produk nyata)
   https://help.loyverse.com/help/offline-work-of-pos
   → Konteks: bagaimana POS komersial menangani penjualan offline (struk tersimpan lokal, sinkron belakangan).

10. **majoo** — *"Aplikasi Kasir Online"* (referensi pasar Indonesia)
    https://majoo.id/aplikasi-kasir-online
    → Konteks: klaim "bisa digunakan tanpa internet; data transaksi otomatis terkirim saat online" pada POS lokal Indonesia.

> **Catatan:** sumber-sumber di atas adalah materi eksternal (data), dipakai untuk grounding keputusan desain. Semua keputusan akhir tetap milik pemilik project.
