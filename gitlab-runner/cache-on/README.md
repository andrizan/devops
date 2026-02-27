Dengan stack **PHP, Node.js, dan Golang**

---

```toml
concurrent = 6
check_interval = 0

[session_server]
  session_timeout = 3600

[[runners]]
  name = "docker-runner-01"
  url = "https://gitlab.com"
  token = "SECRET_TOKEN"
  executor = "docker"
  request_concurrency = 6
  tag_list = ["install", "test", "build", "deploy", "release", "shared"]

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
      "/srv/gitlab-runner/cache/go/pkg:/root/go/pkg:rw",          # Go module cache
      "/srv/gitlab-runner/cache/go/build:/root/.cache/go-build:rw", # Go build cache

      # Docker BuildKit
      "/srv/docker-buildkit-cache:/buildkit-cache:rw",

      "/var/run/docker.sock:/var/run/docker.sock",
      "/certs/client",
    ]

    shm_size = 2147483648
    cpus = "0.8"
    memory = "1300m"
    memory_swap = "1300m"
    memory_reservation = "900m"
    network_mode = "bridge"
    pull_policy = ["if-not-present"]
    helper_image = "gitlab/gitlab-runner-helper:ubuntu-x86_64-v18.5.0"

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
    "/tmp" = "rw,noexec,nosuid,size=512m"
    "/run" = "rw,noexec,nosuid,size=512m"
```

---

## Estimasi Alokasi Cache di Disk

| Cache | Direktori Host | Estimasi |
|---|---|---|
| Composer (PHP) | `/srv/gitlab-runner/cache/composer` | ~3 GB |
| npm / yarn / pnpm | `/srv/gitlab-runner/cache/npm` dll | ~5 GB |
| Go module cache | `/srv/gitlab-runner/cache/go/pkg` | ~3 GB |
| Go build cache | `/srv/gitlab-runner/cache/go/build` | ~3 GB |
| Docker BuildKit | `/srv/docker-buildkit-cache` | ~10 GB |
| **Total** | | **~24 GB** |

---

## Siapkan Direktori di Host

```bash
# Buat direktori
sudo mkdir -p /srv/gitlab-runner/{config,cache/{composer,npm,yarn,pnpm,go/pkg,go/build}}
sudo mkdir -p /srv/docker-buildkit-cache

# Set owner ke root
sudo chown -R root:root /srv/gitlab-runner
sudo chown -R root:root /srv/docker-buildkit-cache
sudo chmod -R 755 /srv/gitlab-runner
sudo chmod -R 755 /srv/docker-buildkit-cache
```

---

## Script Cleanup

Berikut update script cleanup lengkap dengan crontab:

```bash
sudo nano /usr/local/bin/gitlab-runner-cache-cleanup.sh
```

```bash
#!/bin/bash

LOG="/var/log/gitlab-runner-cache-cleanup.log"
MAX_LOG_SIZE_MB=50

# Rotasi log jika melebihi 50MB
if [ -f "$LOG" ] && [ $(du -sm "$LOG" | awk '{print $1}') -gt $MAX_LOG_SIZE_MB ]; then
  mv "$LOG" "${LOG}.old"
fi

echo "=== Cache Cleanup $(date) ===" >> $LOG

declare -A CACHE_DIRS=(
  ["Composer"]="/srv/gitlab-runner/cache/composer:3"
  ["npm"]="/srv/gitlab-runner/cache/npm:3"
  ["yarn"]="/srv/gitlab-runner/cache/yarn:2"
  ["pnpm"]="/srv/gitlab-runner/cache/pnpm:2"
  ["Go Module"]="/srv/gitlab-runner/cache/go/pkg:3"
  ["Go Build"]="/srv/gitlab-runner/cache/go/build:3"
  ["BuildKit"]="/srv/docker-buildkit-cache:10"
)

for NAME in "${!CACHE_DIRS[@]}"; do
  IFS=":" read -r DIR MAX_GB <<< "${CACHE_DIRS[$NAME]}"

  # Skip jika direktori tidak ada
  if [ ! -d "$DIR" ]; then
    echo "$NAME: direktori $DIR tidak ditemukan, skip." >> $LOG
    continue
  fi

  # Hapus file tidak diakses lebih dari 3 hari
  find "$DIR" -atime +3 -type f -delete >> $LOG 2>&1
  find "$DIR" -empty -type d -delete >> $LOG 2>&1

  # Cek ukuran
  CURRENT=$(du -sg "$DIR" 2>/dev/null | awk '{print $1}')
  echo "$NAME: ${CURRENT:-0}GB / ${MAX_GB}GB" >> $LOG

  # Paksa hapus file terlama jika melebihi batas
  if [ "${CURRENT:-0}" -gt "$MAX_GB" ]; then
    echo "$NAME melebihi batas, menghapus file terlama..." >> $LOG
    find "$DIR" -type f -printf '%A+ %p\n' | sort | head -100 | awk '{print $2}' | xargs rm -f
  fi
done

# Bersihkan Docker resources
echo "Membersihkan Docker resources..." >> $LOG
docker image prune -a --filter "until=72h" --force >> $LOG 2>&1
docker container prune --force >> $LOG 2>&1
docker volume prune --force >> $LOG 2>&1
docker network prune --force >> $LOG 2>&1

# Cek total penggunaan disk
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
DISK_USAGE_PCT=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
echo "Penggunaan disk: ${DISK_USAGE}" >> $LOG

# Peringatan jika disk > 80%
if [ "$DISK_USAGE_PCT" -gt 80 ]; then
  echo "⚠️  PERINGATAN: Disk usage ${DISK_USAGE}, melebihi 80%!" >> $LOG
fi

echo "=== Selesai $(date) ===" >> $LOG
echo "" >> $LOG
```

```bash
# Beri permission
sudo chmod +x /usr/local/bin/gitlab-runner-cache-cleanup.sh
```

---

## Daftarkan ke Crontab

```bash
sudo crontab -e
```

Tambahkan baris berikut:

```bash
# ====================================
# GitLab Runner Cache Cleanup
# ====================================

# Cleanup rutin setiap hari jam 01:00
0 1 * * * /usr/local/bin/gitlab-runner-cache-cleanup.sh

# Cleanup darurat jika disk > 85% (cek setiap 30 menit)
*/30 * * * * df / | awk 'NR==2 {gsub("%",""); if($5>85) system("/usr/local/bin/gitlab-runner-cache-cleanup.sh")}'

# Cleanup Docker saja setiap 12 jam (lebih ringan)
0 */12 * * * docker image prune -a --filter "until=72h" --force >> /var/log/gitlab-runner-cache-cleanup.log 2>&1
```

---

## Verifikasi Crontab & Test

```bash
# Lihat crontab yang terdaftar
sudo crontab -l

# Test jalankan manual
sudo /usr/local/bin/gitlab-runner-cache-cleanup.sh

# Monitor log
tail -f /var/log/gitlab-runner-cache-cleanup.log
```

---

## Ringkasan Jadwal Cleanup

| Jadwal | Aksi |
|---|---|
| Setiap hari jam 01:00 | Cleanup penuh semua cache + Docker |
| Setiap 30 menit | Cek disk, cleanup darurat jika > 85% |
| Setiap 12 jam | Cleanup Docker image saja |

---

## Contoh `.gitlab-ci.yml`

```yaml
# PHP
php-install:
  image: php:8.3
  tags: [install]
  script:
    - composer install --no-interaction --prefer-dist
  # Cache otomatis via volume /root/.composer/cache

# Node.js
node-install:
  image: node:20-alpine
  tags: [install]
  script:
    - npm ci
  # Cache otomatis via volume /root/.npm

# Golang
go-build:
  image: golang:1.22
  tags: [build]
  script:
    - go mod download
    - go build ./...
  # Cache otomatis via volume /root/go/pkg dan /root/.cache/go-build

# Build Docker Image
build-image:
  tags: [build]
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
