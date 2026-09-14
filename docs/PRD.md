# 📱 PRD — Kasirin: Offline-First Mobile POS

> **Tagline:** Kasir yang tetap jualan walau internet mati — lalu menyatu sendiri saat online.
>
> **Status:** Blueprint (pre-development) · **Versi:** 1.0 · **Pemilik:** Samid
> **Tujuan utama:** Flagship portofolio untuk melamar kerja sebagai engineer (backend / mobile / fullstack).

---

## 1. Latar Belakang & Masalah

Warung, kafe kecil, dan toko di Indonesia sering:
- Internetnya tidak stabil atau mati (pulsa habis, WiFi down, sinyal jelek).
- Punya **lebih dari satu kasir/HP** yang harus jalan bareng.
- Kehilangan data penjualan kalau aplikasi kasir bergantung 100% ke server.

Aplikasi POS yang ada kebanyakan **online-only**: begitu internet mati, kasir berhenti. Yang offline-first biasanya mahal atau tertutup.

**Masalah inti yang ingin dipecahkan:**
> Bagaimana membuat aplikasi kasir yang **bisa transaksi penuh tanpa internet**, di **banyak device sekaligus**, lalu **menyatu otomatis (converge)** tanpa data dobel, hilang, atau konflik — saat koneksi kembali?

Ini adalah **masalah distributed systems** yang nyata, bukan sekadar CRUD.

---

## 2. Tujuan & Non-Tujuan

### ✅ Tujuan (Goals)
1. Kasir bisa **buka transaksi, tambah item, bayar, cetak struk** — 100% tanpa internet.
2. Data transaksi **tersimpan lokal** dan tidak pernah hilang meski app ditutup / HP restart.
3. Saat online, data **sync otomatis** ke server tanpa tombol manual.
4. **Multi-device**: 2+ HP kasir + 1 dashboard owner, semua **converge ke state yang sama**.
5. **Tanpa duplikasi**: retry sync (karena jaringan putus-nyambung) tidak boleh bikin transaksi dobel.
6. Owner bisa lihat **penjualan live** di dashboard saat kasir online.

### ❌ Non-Tujuan (sengaja TIDAK dibangun, biar fokus)
- ❌ Payment gateway / integrasi EDC / QRIS real.
- ❌ Multi-tenant + billing/langganan.
- ❌ Modul akuntansi, hutang-piutang, pembelian ke supplier.
- ❌ Manajemen karyawan, payroll, shift.
- ❌ Cetak ke printer thermal fisik (cukup preview struk di layar + share PDF).
- ❌ Skala produksi (jutaan user). Fokus: **kualitas sync engine**, bukan skala.

> **Prinsip scope:** Lebih baik 1 fitur sync yang **benar dan bisa didemokan** daripada 10 fitur yang setengah jadi.

---

## 3. Target User & Skenario

### Persona
| Persona | Peran | Butuh |
|---|---|---|
| **Rina** | Kasir warung | Cepat, offline, anti-error |
| **Budi** | Pemilik toko (2 cabang) | Lihat penjualan real-time, tanpa rekap manual |

### Skenario Utama (User Story)
1. **S1 — Jualan offline:** Rina buka app di HP, internet mati. Dia tetap bisa pilih produk, hitung total, pilih metode bayar, dan simpan transaksi. App menampilkan badge *"3 transaksi menunggu sync"*.
2. **S2 — Online lagi:** Internet nyala. Dalam beberapa detik, badge berubah jadi *"Semua tersinkron ✓"*. Tidak ada tombol apa pun yang ditekan.
3. **S3 — Dua kasir:** Rina (HP A) dan Sari (HP B) jualan bareng. Keduanya offline. Saat online, penjualan keduanya muncul di server **tanpa duplikat** dan **stok berkurang dengan benar**.
4. **S4 — Owner live:** Budi buka dashboard di laptop. Setiap transaksi baru dari kasir muncul **real-time** di feed & grafik.
5. **S5 — Edit bentrok:** Rina dan Sari sama-sama ubah harga produk yang sama saat offline. Saat sync, sistem memilih versi yang menang **secara deterministik & konsisten di semua device** (tidak ada yang "beda hasil").

---

## 4. Fitur (MoSCoW)

### 🔴 Must Have (inti — kalau ini gagal, project gagal)
- **F1** CRUD Produk (nama, harga, stok, kategori) — offline-first.
- **F2** Layar Kasir: cari produk, keranjang, ubah qty, diskon sederhana.
- **F3** Simpan transaksi + hitung total + pilih metode bayar (tunai/QRIS-manual).
- **F4** Riwayat transaksi lokal + detail + preview struk.
- **F5** **Local DB persisten** (Drift/SQLite) — data selamat saat app ditutup.
- **F6** **Outbox pattern**: setiap perubahan tercatat sebagai event yang menunggu dikirim.
- **F7** **Sync engine**: push event ke server + pull perubahan, otomatis saat online.
- **F8** **Idempotency**: retry tidak menghasilkan transaksi dobel.
- **F9** **Indikator status sync**: badge "pending / syncing / synced / offline".
- **F10** Backend Go: endpoint sync (push/pull), Postgres sebagai event log + state.

### 🟡 Should Have (bikin "wow" & lengkap)
- **F11** **Conflict resolution deterministik** (HLC + LWW per-field untuk edit produk).
- **F12** **Stok sebagai derived state** (dihitung dari event penjualan → bebas konflik).
- **F13** Dashboard Owner (Next.js): feed penjualan live + grafik harian + total.
- **F14** **Realtime push** ke dashboard (SSE/WebSocket) saat event masuk.
- **F15** Auth sederhana (device token / user login) untuk backend.
- **F16** Halaman **"Sync Inspector"**: daftar event mentah + status (alat debug & bukti teknis di video demo).

### 🟢 Could Have (kalau ada waktu)
- **F17** Barcode scan (kamera) untuk cari produk.
- **F18** Export laporan CSV.
- **F19** Multi-cabang (produk & penjualan per cabang).
- **F20** Unit + integration test otomatis di CI (GitHub Actions).

### ⚫ Won't Have (v1)
- Semua poin di bagian Non-Tujuan.

---

## 5. Metrik Sukses

Karena ini project portofolio, "sukses" = **bisa membuktikan skill**. Target terukur:

| # | Metrik | Target |
|---|---|---|
| M1 | Transaksi bisa dibuat tanpa internet | 100% fitur kasir jalan offline |
| M2 | Data selamat setelah app force-close | 0 data hilang |
| M3 | Konvergensi multi-device | 2 device → state identik dalam <5 detik setelah online |
| M4 | Anti-duplikat saat retry | 0 transaksi dobel dari 100 push yang di-retry |
| M5 | Conflict resolution | 2 edit bentrok → hasil sama di semua device, 100% |
| M6 | Test coverage sync engine | ≥ 80% untuk paket `sync` |
| M7 | Video demo | ≤ 90 detik, jelas menunjukkan S1–S5 |

**Metrik portofolio (yang dibaca recruiter):** project ini membuktikan kemampuan pada → *distributed systems, event sourcing, CRDT/conflict resolution, offline-first mobile, Go backend, realtime*.

---

## 6. Arsitektur Singkat

> Detail teknis lengkap ada di `ARCHITECTURE.md`.

```
┌──────────────────┐            ┌──────────────────┐
│  Flutter Kasir   │            │  Flutter Kasir   │
│   (Device A)     │            │   (Device B)     │
│  ┌────────────┐  │            │  ┌────────────┐  │
│  │ Drift DB   │  │            │  │ Drift DB   │  │
│  │ + Outbox   │  │            │  │ + Outbox   │  │
│  └────────────┘  │            │  └────────────┘  │
└────────┬─────────┘            └────────┬─────────┘
         │   push/pull (HTTP, retry-safe) │
         └───────────────┬────────────────┘
                         ▼
               ┌───────────────────┐
               │  Go API (Fiber)   │
               │  /sync/push       │
               │  /sync/pull       │
               └─────────┬─────────┘
                         ▼
               ┌───────────────────┐      ┌────────────────┐
               │   PostgreSQL      │◄────►│  Next.js Owner │
               │  event log +      │ SSE  │   Dashboard    │
               │  materialized     │      └────────────────┘
               └───────────────────┘
```

**Ide inti yang bikin elegan:**
- Transaksi penjualan bersifat **append-only (immutable)** → secara alami **tidak pernah konflik**.
- Stok **tidak disimpan sebagai angka yang di-overwrite**, tapi **diturunkan** dari event penjualan → bebas race condition.
- Hanya **edit produk** (harga/nama) yang bisa bentrok → diselesaikan dengan **HLC + Last-Write-Wins per field**.

---

## 7. Tech Stack

| Layer | Pilihan | Alasan |
|---|---|---|
| Mobile | **Flutter 3.x** + **Drift** (SQLite) + **Riverpod** + `go_router` | Offline-first butuh SQL lokal transaksional; Riverpod untuk state yang testable |
| Backend | **Go 1.25** + **Fiber v2** + **pgx** | Cepat, cocok untuk high-throughput & concurrency; lu sudah pakai di `vimind` |
| DB | **PostgreSQL 16** | Event log + materialized view; JSONB untuk payload event |
| Realtime | **SSE** (Server-Sent Events) | Simpel, cukup untuk dashboard push; upgrade ke WebSocket kalau perlu |
| Dashboard | **Next.js 15** + Tailwind | Familiar; render grafik & feed live |
| Infra | **Docker Compose** + **GitHub Actions** | Reproducible; CI jalanin test |

> Semua stack **sudah lu kuasai** — jadi energinya habis untuk *masalah sulitnya* (sync), bukan belajar tool baru.

---

## 8. Roadmap (santai, tanpa deadline)

| Milestone | Isi | Estimasi |
|---|---|---|
| **M0 — Fondasi** | Repo, struktur, `docker-compose` (Postgres), skeleton Go + Flutter, CI kosong | 2–3 hari |
| **M1 — POS Lokal** | Flutter + Drift: CRUD produk, kasir, transaksi, struk. **Belum ada sync.** | ~1 minggu |
| **M2 — Backend + Sync API** | Go: `/sync/push` & `/sync/pull`, idempotency, event log di Postgres | ~1 minggu |
| **M3 — Sync Engine (client)** | Outbox, sync worker, apply remote events, status badge | ~1–2 minggu |
| **M4 — Konflik & Multi-device** | HLC, LWW per-field, stok derived, uji 2 device converge | ~1 minggu |
| **M5 — Dashboard Owner** | Next.js: feed live (SSE), grafik, total harian | ~1 minggu |
| **M6 — Polish & Demo** | UI, Sync Inspector, README "jual", **rekam video demo** | ~1 minggu |

**Total: ~7–8 minggu santai.** Bisa dipotong jadi 3 minggu kalau dikejar.

---

## 9. Skenario Video Demo (≤ 90 detik)

1. **0:00** — Buka app di HP. Tampilkan produk & layar kasir. UI rapi, dark, monospace untuk angka.
2. **0:10** — Jual 2 item normal (online). Badge: *"Synced ✓"*. Muncul di dashboard owner live.
3. **0:20** — **Aktifkan mode pesawat.** Badge berubah: *"Offline"*.
4. **0:25** — Tetap jual 5 transaksi. Tiap transaksi langsung tersimpan. Badge: *"5 menunggu sync"*.
5. **0:40** — Buka **HP kedua** (device B), tunjukkan dia belum tahu transaksi itu.
6. **0:50** — **Matikan mode pesawat.** Tonton badge *"5 → 4 → 3 → 2 → 1 → Semua tersinkron ✓"* dalam hitungan detik.
7. **1:05** — HP B **refresh otomatis**, sekarang menampilkan transaksi yang sama. **State identik.**
8. **1:15** — Dashboard owner: feed & grafik **melompat live** menerima semua transaksi baru.
9. **1:25** — (Bonus) Tunjukkan **Sync Inspector**: daftar event mentah + `server_seq`. → bukti "ini beneran engineered".
10. **1:30** — Selesai. Overlay: arsitektur + nama stack.

---

## 10. Risiko & Mitigasi

| Risiko | Mitigasi |
|---|---|
| **Bug sync sulit di-debug** (classic offline-first pain) | Bangun **Sync Inspector** sejak awal (F16); selalu bisa lihat event mentah & status |
| **Scope creep** (kejebak nambah fitur) | Disiplin ke Non-Tujuan; tanya "apakah ini nunjukin skill sync?" kalau tidak → skip |
| **Over-engineering CRDT** | Mulai dari yang cukup: append-only + LWW. CRDT penuh hanya kalau perlu |
| **Data dobel** | `event_id` (UUID) + `ON CONFLICT DO NOTHING` di server |
| **Momentum hilang** | Milestone kecil yang selalu bisa "kelar" & bisa didemokan tiap tahap |

---

## 11. Definisi Selesai (Definition of Done — v1)

Project dinyatakan **selesai & siap dipajang** bila:
- [ ] Semua fitur **Must Have** jalan.
- [ ] Skenario demo (bagian 9) bisa direkam **sekali jalan tanpa edit**.
- [ ] 2 device terbukti converge (M3) dan anti-duplikat (M4).
- [ ] `README.md` berisi: masalah, solusi, diagram arsitektur, GIF/video, cara jalanin.
- [ ] Test sync engine ≥ 80% (M6).
- [ ] Repo publik di GitHub, riwayat commit rapi (bukan 1 commit "initial").

---

## 12. Nama & Branding

- **Nama:** **Kasirin** (dari "kasir" + akhiran ramah).
- **Tagline:** *"Jualan terus, walau internet mati."*
- **Vibe UI:** bersih, gelap (dark), angka monospace, tombol besar (dipakai buru-buru pakai jempol).
