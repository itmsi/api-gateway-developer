# Panduan Setup Kong API Gateway (Developer)

Dokumen ini menjelaskan cara menyiapkan lingkungan Kong API Gateway berbasis Docker untuk skenario developer, serta prosedur restart ketika terdapat pembaruan konfigurasi route/service.

## 1. Persiapan Awal

1. Pastikan Docker Engine dan Docker Compose telah terpasang di server.
   - **Minimum Docker Compose**: Versi 2.1+ (untuk dukungan `host-gateway`)
   - Untuk Ubuntu/Linux: Pastikan menggunakan Docker Compose V2 atau lebih baru
2. Kloning repositori ini atau salin berkas konfigurasi ke server tujuan.
3. Pastikan port berikut belum dipakai oleh layanan lain:
   - `9588` untuk Kong Proxy
   - `9589` untuk Kong Admin API
   - `9590` untuk Kong Admin GUI

### 1.1 Kompatibilitas Platform

Konfigurasi ini kompatibel dengan:
- ✅ **macOS** (Docker Desktop)
- ✅ **Windows** (Docker Desktop)
- ✅ **Ubuntu/Linux** (Docker Compose V2.1+)

**Catatan Penting untuk Ubuntu/Linux:**
- Konfigurasi menggunakan `host.docker.internal` dengan `host-gateway` yang memerlukan Docker Compose versi 2.1 atau lebih baru
- Jika menggunakan Docker Compose versi lama, Anda perlu mengubah `extra_hosts` di `docker-compose.developer.yml`:
  ```yaml
  extra_hosts:
    - "host.docker.internal:172.17.0.1"  # Gunakan IP gateway Docker bridge
  ```
- Atau gunakan IP host secara langsung di `config/kong.yml` jika `host.docker.internal` tidak tersedia

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
- **Error "An invalid response was received from the upstream server"** atau **Status 499 (Client Closed Connection)**:
  - Pastikan service upstream berjalan di host (test langsung dari host):
    ```bash
    curl http://localhost:9518/api/auth/sso/login
    ```
  - **PENTING**: Pastikan service upstream listen di `0.0.0.0`, bukan hanya `127.0.0.1`:
    ```bash
    # Cek apakah service listen di 0.0.0.0 atau 127.0.0.1
    netstat -tlnp | grep 9518
    # atau
    ss -tlnp | grep 9518
    ```
    Jika hanya listen di `127.0.0.1`, service tidak bisa diakses dari container Docker. Ubah konfigurasi service untuk listen di `0.0.0.0:9518`.
  - Verifikasi `host.docker.internal` terdaftar di `/etc/hosts` container:
    ```bash
    docker exec msi-api-gateway-developer-kong cat /etc/hosts | grep host.docker.internal
    ```
    Seharusnya menampilkan entry untuk `host.docker.internal`
  - Test koneksi dari container ke host (alternatif jika `/dev/tcp` tidak tersedia):
    ```bash
    # Test dengan getent (jika tersedia)
    docker exec msi-api-gateway-developer-kong getent hosts host.docker.internal
    
    # Atau test langsung dengan Kong Admin API untuk trigger request
    curl -X POST http://localhost:9589/services/sso-service/routes/sso-login-route/plugins \
      -H "Content-Type: application/json" \
      -d '{"name":"request-termination"}'
    # Lalu hapus plugin tersebut dan test request
    ```
  - Test koneksi menggunakan Kong Admin API untuk melihat status service:
    ```bash
    curl http://localhost:9589/services/sso-service
    ```
  - Cek log Kong untuk detail error (cari error terkait upstream):
    ```bash
    docker logs msi-api-gateway-developer-kong 2>&1 | grep -i "upstream\|error\|failed" | tail -20
    ```
  - Jika `host.docker.internal` tidak terdaftar, pastikan Docker Compose versi 2.1+:
    ```bash
    docker compose version
    ```
  - Jika menggunakan Docker Compose versi lama, ubah `extra_hosts` menjadi:
    ```yaml
    extra_hosts:
      - "host.docker.internal:172.17.0.1"
    ```
    Lalu restart container: `docker compose -f docker-compose.developer.yml restart kong`
  - **Jika service listen di IPv6 (`:::9518`) tapi Kong tidak bisa connect**:
    - Solusi 1: Gunakan IP langsung di `config/kong.yml`:
      ```yaml
      url: http://172.17.0.1:9518  # Ganti host.docker.internal dengan IP gateway
      ```
    - Solusi 2: Pastikan service juga listen di IPv4 (`0.0.0.0:9518`), bukan hanya IPv6
    - Solusi 3: Test dengan IP gateway Docker bridge:
      ```bash
      # Cari IP gateway
      docker network inspect msi-api-gateway-developer-network | grep Gateway
      # Gunakan IP tersebut di config/kong.yml
      ```

## 6. Pemeliharaan

- Simpan cadangan `config/kong.yml` sebelum melakukan perubahan besar.
- Gunakan sistem versioning (Git) agar perubahan konfigurasi terdokumentasi.
- Jadwalkan pengujian berkala terhadap route penting menggunakan skrip otomatis atau alat monitoring.

Dengan mengikuti langkah-langkah di atas, deployment Kong API Gateway lingkungan developer dapat berjalan konsisten dan mudah dipelihara.
