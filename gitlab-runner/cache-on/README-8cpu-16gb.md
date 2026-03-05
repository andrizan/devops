# GitLab Runner — Docker Executor (8 CPU / 16 GB RAM / 90 GB Storage)

Konfigurasi GitLab Runner dengan executor Docker untuk stack **PHP, Node.js, dan Golang**.

---

## Spesifikasi Server

| Komponen | Spesifikasi |
|---|---|
| CPU | 8 Core |
| RAM | 16 GB |
| Storage | 90 GB (tersedia) |
| OS | Ubuntu 24.04 |

---

## Estimasi Alokasi Storage

| Kebutuhan | Alokasi |
|---|---|
| OS + GitLab Runner binary | ~5 GB |
| Docker images & layers | ~25 GB |
| BuildKit cache | ~15 GB |
| GitLab Runner cache (composer/npm/yarn/go) | ~25 GB |
| Log files | ~2 GB |
| Buffer/headroom | ~18 GB |
| **Total** | **~90 GB** |

---

## Estimasi Alokasi Cache di Disk

| Cache | Direktori Host | Estimasi |
|---|---|---|
| Composer (PHP) | `/srv/gitlab-runner/cache/composer` | ~3 GB |
| npm | `/srv/gitlab-runner/cache/npm` | ~3 GB |
| yarn | `/srv/gitlab-runner/cache/yarn` | ~2 GB |
| pnpm | `/srv/gitlab-runner/cache/pnpm` | ~2 GB |
| Go module cache | `/srv/gitlab-runner/cache/go/pkg` | ~3 GB |
| Go build cache | `/srv/gitlab-runner/cache/go/build` | ~3 GB |
| Docker BuildKit | `/srv/docker-buildkit-cache` | ~8 GB |
| **Total** | | **~24 GB** |

---

## Struktur Direktori Proyek

```
~/glrunner/
├── config.toml
├── docker-compose.yml
└── cleanup.sh
```

---

## Konfigurasi Runner

### `config.toml`

```toml
concurrent = 16
check_interval = 0

[session_server]
  session_timeout = 3600

[[runners]]
  name = "GL-Runner-Jakarta01"
  url = "https://gitlab.com"
  token = "SECRET_TOKEN"
  executor = "docker"
  request_concurrency = 16
  tag_list = ["install-autoscale", "test-autoscale", "build-autoscale", "deploy-autoscale", "release-autoscale", "shared-autoscale"]

  [runners.custom_build_dir]

  [runners.cache]
    MaxUploadedArchiveSize = 0

  [runners.docker]
    tls_verify = false
    image = "ubuntu:24.04"
    privileged = true
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false

    volumes = [
      "/srv/gitlab-runner/cache:/cache:rw",

      # PHP (Composer)
      "/srv/gitlab-runner/cache/composer:/root/.composer/cache:rw",

      # Node.js
      "/srv/gitlab-runner/cache/npm:/root/.npm:rw",
      "/srv/gitlab-runner/cache/yarn:/root/.yarn:rw",
      "/srv/gitlab-runner/cache/pnpm:/root/.local/share/pnpm/store:rw",

      # Golang
      "/srv/gitlab-runner/cache/go/pkg:/root/go/pkg:rw",            # Go module cache
      "/srv/gitlab-runner/cache/go/build:/root/.cache/go-build:rw",  # Go build cache

      # Docker BuildKit
      "/srv/docker-buildkit-cache:/buildkit-cache:rw",

      "/var/run/docker.sock:/var/run/docker.sock",
      "/certs/client",
    ]

    shm_size = 4294967296      # 4 GB (25% dari 16 GB RAM)
    cpus = "6.0"               # 6 dari 8 core (sisakan 2 untuk OS & runner)
    memory = "12g"             # 12 GB per job maksimal
    memory_swap = "12g"
    memory_reservation = "8g"  # 8 GB soft limit
    network_mode = "bridge"
    pull_policy = ["if-not-present"]
    helper_image = "gitlab/gitlab-runner-helper:ubuntu-x86_64-v18.9.0"

    environment = [
      "DOCKER_DRIVER=overlay2",
      "DOCKER_TLS_CERTDIR=/certs",
      "DOCKER_BUILDKIT=1",
      "BUILDKIT_INLINE_CACHE=1",

      # Golang cache path
      "GOPATH=/root/go",
      "GOCACHE=/root/.cache/go-build",
      "GOMODCACHE=/root/go/pkg/mod",

      # Composer cache path
      "COMPOSER_CACHE_DIR=/root/.composer/cache",

      # npm cache path
      "NPM_CONFIG_CACHE=/root/.npm",
    ]

  [runners.docker.tmpfs]
    "/tmp" = "rw,noexec,nosuid,size=1024m"  # 1 GB
    "/run" = "rw,noexec,nosuid,size=512m"   # 512 MB
```

### `docker-compose.yml`

```yaml
services:
  gitlab-runner:
    image: gitlab/gitlab-runner:ubuntu-v18.9.0
    container_name: GL-Runner-Jakarta01
    restart: unless-stopped
    privileged: true
    cpus: "7.0"            # 7 dari 8 core untuk runner container
    mem_limit: "15g"       # 15 GB limit (sisakan 1 GB untuk OS)
    mem_reservation: "10g"
    shm_size: "4g"
    storage_opt:
      size: "35g"          # Batas storage container (Docker layer)
    volumes:
      # Konfigurasi runner
      - /srv/gitlab-runner/config:/etc/gitlab-runner
      # Docker socket
      - /var/run/docker.sock:/var/run/docker.sock
      # Cache PHP (Composer)
      - /srv/gitlab-runner/cache/composer:/root/.composer/cache
      # Cache Node.js
      - /srv/gitlab-runner/cache/npm:/root/.npm
      - /srv/gitlab-runner/cache/yarn:/root/.yarn
      - /srv/gitlab-runner/cache/pnpm:/root/.local/share/pnpm/store
      # Cache Golang
      - /srv/gitlab-runner/cache/go/pkg:/root/go/pkg
      - /srv/gitlab-runner/cache/go/build:/root/.cache/go-build
      # Cache Docker BuildKit
      - /srv/docker-buildkit-cache:/buildkit-cache
      # Cache umum
      - /srv/gitlab-runner/cache:/cache
    environment:
      - DOCKER_HOST=unix:///var/run/docker.sock
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
    networks:
      - gitlab-runner-net

networks:
  gitlab-runner-net:
    driver: bridge
```

---

## Ringkasan Parameter Kunci

| Parameter | Nilai | Keterangan |
|---|---|---|
| `concurrent` | 16 | Maksimal job paralel |
| `request_concurrency` | 16 | Konkurensi request ke GitLab |
| `cpus` (job) | `6.0` | CPU per job container |
| `memory` (job) | `12g` | RAM maksimal per job |
| `memory_reservation` | `8g` | RAM soft limit per job |
| `shm_size` | 4 GB | Shared memory |
| `/tmp` tmpfs | 1 GB | Temp storage in-memory |
| `/run` tmpfs | 512 MB | Run storage in-memory |
| `mem_limit` (compose) | `15g` | RAM total runner container |
| `cpus` (compose) | `7.0` | CPU total runner container |
| BuildKit keep-storage | 8 GB | Batas cache BuildKit |

---

## Persiapan Direktori di Host

```bash
# Buat direktori proyek runner
mkdir -p ~/glrunner

# Buat direktori cache di /srv
sudo mkdir -p /srv/gitlab-runner/{config,cache/{composer,npm,yarn,pnpm,go/pkg,go/build}}
sudo mkdir -p /srv/docker-buildkit-cache

# Set permission
sudo chown -R root:root /srv/gitlab-runner
sudo chown -R root:root /srv/docker-buildkit-cache
sudo chmod -R 755 /srv/gitlab-runner
sudo chmod -R 755 /srv/docker-buildkit-cache
```

---

## Script Cleanup Cache

Simpan script berikut ke `~/glrunner/cleanup.sh`:

```bash
#!/bin/bash
set -uo pipefail

LOG="/var/log/gl-runner-cleanup.log"
MAX_LOG_SIZE_MB=50

# Rotasi log jika melebihi 50 MB
if [ -f "$LOG" ] && [ $(du -sm "$LOG" | awk '{print $1}') -gt $MAX_LOG_SIZE_MB ]; then
  mv "$LOG" "${LOG}.$(date +%Y%m%d-%H%M%S).old"
  ls -t "${LOG}".*.old 2>/dev/null | tail -n +6 | xargs rm -f
fi

echo "=== Cache Cleanup $(date) ===" >> $LOG

declare -A CACHE_DIRS=(
  ["Composer"]="/srv/gitlab-runner/cache/composer:3"
  ["npm"]="/srv/gitlab-runner/cache/npm:3"
  ["yarn"]="/srv/gitlab-runner/cache/yarn:2"
  ["pnpm"]="/srv/gitlab-runner/cache/pnpm:2"
  ["Go Module"]="/srv/gitlab-runner/cache/go/pkg:3"
  ["Go Build"]="/srv/gitlab-runner/cache/go/build:3"
)

for NAME in "${!CACHE_DIRS[@]}"; do
  IFS=":" read -r DIR MAX_GB <<< "${CACHE_DIRS[$NAME]}"

  if [ ! -d "$DIR" ]; then
    echo "$NAME: direktori $DIR tidak ditemukan, skip." >> $LOG
    continue
  fi

  # Hapus file tidak diakses lebih dari 3 hari
  find "$DIR" -atime +3 -type f -delete >> $LOG 2>&1
  find "$DIR" -empty -type d -delete >> $LOG 2>&1

  # Cek ukuran dalam MB untuk akurasi
  CURRENT_MB=$(du -sm "$DIR" 2>/dev/null | awk '{print $1}')
  MAX_MB=$(( MAX_GB * 1024 ))
  echo "$NAME: ${CURRENT_MB}MB / ${MAX_MB}MB (${MAX_GB}GB)" >> $LOG

  # Paksa hapus file terlama jika melebihi batas
  if [ "${CURRENT_MB:-0}" -gt "$MAX_MB" ]; then
    echo "$NAME melebihi batas, menghapus file terlama..." >> $LOG
    find "$DIR" -type f -printf '%A+ %p\n' | sort | head -100 | awk '{print $2}' | \
      tee -a "$LOG" | xargs rm -f
  fi
done

# BuildKit — gunakan docker buildx prune (bukan find -atime)
echo "Membersihkan BuildKit cache..." >> $LOG
if [ -d "/srv/docker-buildkit-cache" ]; then
  docker buildx prune --filter "until=72h" --keep-storage=8gb -f >> $LOG 2>&1
else
  echo "BuildKit: direktori tidak ditemukan, skip." >> $LOG
fi

# Bersihkan Docker resources
echo "Membersihkan Docker resources..." >> $LOG
docker image prune -a --filter "until=72h" --force >> $LOG 2>&1
docker container prune --force >> $LOG 2>&1
docker volume prune --force >> $LOG 2>&1
docker network prune --force >> $LOG 2>&1

# Cek penggunaan disk /srv
DISK_USAGE=$(df -h /srv | awk 'NR==2 {print $5}')
DISK_USAGE_PCT=$(df /srv | awk 'NR==2 {gsub("%",""); print $5}')
echo "Penggunaan disk /srv: ${DISK_USAGE}" >> $LOG

if [ "$DISK_USAGE_PCT" -gt 85 ]; then
  echo "⚠️  PERINGATAN: Disk usage /srv ${DISK_USAGE}, melebihi 85%!" >> $LOG
fi

echo "=== Selesai $(date) ===" >> $LOG
echo "" >> $LOG
```

```bash
# Beri permission eksekusi
chmod +x ~/glrunner/cleanup.sh
```

---

## Jadwal Crontab

```bash
sudo crontab -e
```

Tambahkan baris berikut:

```bash
# ====================================
# GitLab Runner Cache Cleanup
# ====================================

# Cleanup rutin setiap hari jam 01:00
0 1 * * * /home/ebelanja/glrunner/cleanup.sh

# Cleanup darurat jika disk /srv > 85% (cek setiap 30 menit)
*/30 * * * * df /srv | awk 'NR==2 {gsub("%",""); if($5>85) system("/home/ebelanja/glrunner/cleanup.sh")}'

# Cleanup Docker image saja setiap 12 jam (lebih ringan)
0 */12 * * * docker image prune -a --filter "until=72h" --force >> /var/log/gl-runner-cleanup.log 2>&1
```

> **Catatan:** Sesuaikan `/home/ebelanja/glrunner/cleanup.sh` dengan username aktual di server, atau gunakan path absolut hasil `realpath ~/glrunner/cleanup.sh`.

### Ringkasan Jadwal

| Jadwal | Aksi |
|---|---|
| Setiap hari jam 01:00 | Cleanup penuh semua cache + Docker |
| Setiap 30 menit | Cek disk, cleanup darurat jika /srv > 85% |
| Setiap 12 jam | Cleanup Docker image saja |

---

## Verifikasi & Monitoring

```bash
# Lihat crontab yang terdaftar
sudo crontab -l

# Test jalankan manual
~/glrunner/cleanup.sh

# Monitor log secara real-time
tail -f /var/log/gl-runner-cleanup.log

# Cek penggunaan disk
df -h /srv

# Cek status runner
docker ps | grep gitlab-runner
```

---

## Menjalankan Runner

```bash
# Masuk ke direktori proyek
cd ~/glrunner

# Jalankan runner
docker compose up -d

# Cek log runner
docker compose logs -f
```

---

## Contoh `.gitlab-ci.yml`

```yaml
# PHP — Composer
php-install:
  image: php:8.3
  tags: [install-autoscale]
  script:
    - composer install --no-interaction --prefer-dist
  # Cache otomatis via volume /root/.composer/cache

# Node.js — npm
node-install:
  image: node:20-alpine
  tags: [install-autoscale]
  script:
    - npm ci
  # Cache otomatis via volume /root/.npm

# Golang
go-build:
  image: golang:1.22
  tags: [build-autoscale]
  script:
    - go mod download
    - go build ./...
  # Cache otomatis via volume /root/go/pkg dan /root/.cache/go-build

# Build Docker Image dengan BuildKit
build-image:
  tags: [build-autoscale]
  script:
    - |
      docker build \
        --cache-from registry.example.com/myapp:cache \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        -t registry.example.com/myapp:$CI_COMMIT_SHA \
        -t registry.example.com/myapp:cache \
        .
    - docker push registry.example.com/myapp:$CI_COMMIT_SHA
    - docker push registry.example.com/myapp:cache
```
