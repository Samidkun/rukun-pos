# Panduan Pengguna Kasir & Pemilik Toko — Rukun POS

> **Versi Rilis:** `RILIS-2026.09.14`  
> **Tagline:** *"Jualan terus, walau internet mati."*

---

## 1. Ringkasan Singkat

Rukun POS dirancang khusus untuk toko, warung, dan kafe di Indonesia di mana koneksi internet sering tidak stabil atau terputus. Sistem ini memungkinkan kasir tetap melayani penjualan tanpa hambatan dan data akan otomatis menyatu (*converge*) saat internet kembali menyala.

---

## 2. Alur Kasir Saat Internet Putus (Offline Mode)

### A. Melayani Pembayaran
1. Buka layar **Kasir**. Anda akan melihat badge status di kanan atas bertuliskan **"Offline"** atau **"N Tertunda"**.
2. Pilih produk yang dibeli pelanggan (atau gunakan kolom pencarian di bagian atas).
3. Tekan tombol **"Bayar"** di bilah bawah.
4. Pilih metode pembayaran:
   - **Tunai (Cash)**: Hitung uang dan kembalian.
   - **QRIS Offline**: Scan QRIS statis toko (bukti pembayaran tersimpan lokal).
5. Tekan **"Bayar Rp ..."**.
6. Transaksi langsung berhasil dibuat dan struk belanja dapat dicetak atau disalin.

### B. Penomoran Struk yang Rapi & Tidak Tertukar
Setiap mesin kasir memiliki kode seri mandiri:
- Kasir 1: `T01-000001`, `T01-000002`, dst.
- Kasir 2: `T02-000001`, `T02-000002`, dst.

Nomor struk selalu urut dan tidak akan pernah bentrok atau tertukar dengan kasir lain, meskipun internet mati berjam-jam.

---

## 3. Apa yang Terjadi Saat Internet Kembali Menyala?

Kasir **tidak perlu menekan tombol sinkronisasi manual**.

1. Aplikasi mendeteksi koneksi jaringan secara otomatis.
2. Semua transaksi penjualan yang tersimpan di memori HP akan terkirim ke server pusat secara berurutan.
3. Badge di kanan atas akan otomatis berubah warna menjadi **Hijau ("Tersinkron")**.
4. Di dashboard pemilik toko (Owner), seluruh penjualan yang tadi tertunda akan langsung muncul secara *real-time*.

---

## 4. Penanganan Kasus Khusus: Stok Minus (Overselling C1)

### Situasi:
Stok tersisa 1 porsi. Kasir 1 dan Kasir 2 sedang sama-sama offline dan keduanya menjual 1 porsi kepada pelanggan di waktu yang hampir bersamaan.

### Prinsip Bisnis Rukun:
1. **Penjualan tidak pernah dibatalkan sepihak oleh sistem.** Kedua pelanggan sah telah membayar dan membawa barang.
2. Stok barang akan menunjukkan angka minus (misal: `-1 unit`). Ini adalah **sinyal operasional yang jujur**, bukan kerusakan data.
3. Kasir atau Owner dapat membuka menu **Audit Stok Oversold (C1)**:
   - Tekan tombol **"+5 Restock"** setelah stok fisik di dapur ditambah.
   - Atau tawarkan penggantian produk/refund secara sopan jika barang memang habis.
