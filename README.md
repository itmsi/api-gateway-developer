# Panduan Setup Kong API Gateway (Developer)

Dokumen ini menjelaskan cara menyiapkan lingkungan Kong API Gateway berbasis Docker untuk skenario developer, serta prosedur restart ketika terdapat pembaruan konfigurasi route/service.

## 1. Persiapan Awal

1. Pastikan Docker Engine dan Docker Compose telah terpasang di server.
2. Kloning repositori ini atau salin berkas konfigurasi ke server tujuan.
3. Pastikan port berikut belum dipakai oleh layanan lain:
   - `9588` untuk Kong Proxy
   - `9589` untuk Kong Admin API
   - `9590` untuk Kong Admin GUI

## 2. Struktur Berkas Penting

- `docker-compose.developer.yml` – definisi layanan Kong, image, network, port, dan environment.
- `Dockerfile.kong` – Dockerfile yang menurunkan image resmi `kong:3.4` untuk memberi tag kustom.
- `config/kong.yml` – konfigurasi deklaratif Kong (services, routes, plugins). Update file ini saat menambah atau mengubah konfigurasi.
- `config/resolv.conf` – konfigurasi DNS resolver untuk kontainer Kong.

## 3. Proses Setup & Deploy

1. Bangun image lokal (opsional bila image belum ada atau Dockerfile berubah):
   ```bash
   docker compose -f docker-compose.developer.yml build
   ```
2. Jalankan Kong dalam mode terdetached:
   ```bash
   docker compose -f docker-compose.developer.yml up -d
   ```
3. Verifikasi kontainer berjalan dan `STATUS` "healthy":
   ```bash
   docker ps --filter name=msi-api-gateway-developer-kong
   ```
4. Uji route contoh (opsional):
   ```bash
   curl http://127.0.0.1:9588/example
   ```

## 4. Update Route/Service

Ketika menambahkan atau mengubah route/service di `config/kong.yml`, ikuti langkah berikut.

### 4.1 Update Konfigurasi

1. Edit `config/kong.yml` sesuai kebutuhan (mis. menambah service baru).
2. Simpan perubahan dan pindahkan file ke server bila konfigurasi diedit secara lokal.

### 4.2 Restart Kong untuk Memuat Konfigurasi Baru

Gunakan opsi yang dianggap paling sesuai:

- **Opsi A – Restart Kontainer** (paling mudah, cocok bila downtime singkat diterima)
  ```bash
  docker compose -f docker-compose.developer.yml restart kong
  ```

- **Opsi B – Stop & Up** (berguna bila ingin membersihkan state tertentu)
  ```bash
  docker compose -f docker-compose.developer.yml down --remove-orphans
  docker compose -f docker-compose.developer.yml up -d
  ```

- **Opsi C – Reload Tanpa Downtime Penuh**
  Jika membutuhkan reload cepat tanpa menghentikan kontainer, perintah berikut men-trigger Kong agar membaca ulang konfigurasi deklaratif:
  ```bash
  docker exec msi-api-gateway-developer-kong kong reload
  ```
  Catatan: Pastikan file `kong.yml` valid sebelum menjalankan reload.

## 5. Troubleshooting Singkat

- **Kontainer tidak "healthy"**: cek log dengan `docker logs msi-api-gateway-developer-kong`.
- **Konfigurasi deklaratif invalid**: gunakan perintah `kong config parse /kong/kong.yml` (dijalankan di dalam kontainer) untuk mengetahui kesalahan.
- **Port sudah digunakan**: pastikan tidak ada layanan lain di host yang memakai port 9588-9590, atau ganti mapping port pada `docker-compose.developer.yml`.

## 6. Pemeliharaan

- Simpan cadangan `config/kong.yml` sebelum melakukan perubahan besar.
- Gunakan sistem versioning (Git) agar perubahan konfigurasi terdokumentasi.
- Jadwalkan pengujian berkala terhadap route penting menggunakan skrip otomatis atau alat monitoring.

Dengan mengikuti langkah-langkah di atas, deployment Kong API Gateway lingkungan developer dapat berjalan konsisten dan mudah dipelihara.
