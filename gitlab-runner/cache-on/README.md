# GitLab Runner — Docker Executor

GitLab Runner configuration with Docker executor for **PHP, Node.js, and Golang** stacks.

---

## Project Directory Structure

```
~/glrunner/
└── docker-compose.yml

/srv/gitlab-runner/config/
├── config.toml
└── cleanup.sh
```

---

## Server Specifications

This document covers two server specification variants:

| Component | Variant A | Variant B |
|---|---|---|
| CPU | 4 Core | 8 Core |
| RAM | 8 GB | 16 GB |
| Storage | 90 GB | 90 GB |
| OS | Ubuntu 24.04 | Ubuntu 24.04 |

---

## Storage Allocation Estimate

Storage allocation is identical for both variants since storage is 90 GB in both cases:

| Usage | Allocation |
|---|---|
| OS + GitLab Runner binary | ~5 GB |
| Docker images & layers | ~20 GB |
| BuildKit cache | ~10 GB |
| GitLab Runner cache (composer/npm/yarn/go) | ~15 GB |
| Log files | ~1 GB |
| Buffer/headroom | ~39 GB |
| **Total** | **~90 GB** |

### Cache Directory Allocation

| Cache | Host Directory | Estimate |
|---|---|---|
| Composer (PHP) | `/srv/gitlab-runner/cache/composer` | ~2 GB |
| npm | `/srv/gitlab-runner/cache/npm` | ~2 GB |
| yarn | `/srv/gitlab-runner/cache/yarn` | ~1 GB |
| pnpm | `/srv/gitlab-runner/cache/pnpm` | ~1 GB |
| Go module cache | `/srv/gitlab-runner/cache/go/pkg` | ~2 GB |
| Go build cache | `/srv/gitlab-runner/cache/go/build` | ~2 GB |
| Docker BuildKit | `/srv/docker-buildkit-cache` | ~5 GB |
| **Total** | | **~15 GB** |

---

## Host Directory Setup

The following steps are the same for both variants:

```bash
# Create runner project directory
mkdir -p ~/glrunner

# Create config and cache directories under /srv
sudo mkdir -p /srv/gitlab-runner/config
sudo mkdir -p /srv/gitlab-runner/cache/{composer,npm,yarn,pnpm,go/pkg,go/build}
sudo mkdir -p /srv/docker-buildkit-cache

# Set permissions
sudo chown -R root:root /srv/gitlab-runner
sudo chown -R root:root /srv/docker-buildkit-cache
sudo chmod -R 755 /srv/gitlab-runner
sudo chmod -R 755 /srv/docker-buildkit-cache
```

---

## Runner Configuration

### `config.toml`

> Save to `/srv/gitlab-runner/config/config.toml`

#### Variant A — 4 CPU / 8 GB RAM

```toml
concurrent = 8
check_interval = 0

[session_server]
  session_timeout = 3600

[[runners]]
  name = "GL-Runner-Jakarta01"
  url = "https://gitlab.com"
  token = "SECRET_TOKEN"
  executor = "docker"
  request_concurrency = 8
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
      "/srv/gitlab-runner/cache/composer:/root/.composer/cache:rw",
      "/srv/gitlab-runner/cache/npm:/root/.npm:rw",
      "/srv/gitlab-runner/cache/yarn:/root/.yarn:rw",
      "/srv/gitlab-runner/cache/pnpm:/root/.local/share/pnpm/store:rw",
      "/srv/gitlab-runner/cache/go/pkg:/root/go/pkg:rw",
      "/srv/gitlab-runner/cache/go/build:/root/.cache/go-build:rw",
      "/srv/docker-buildkit-cache:/buildkit-cache:rw",
      "/var/run/docker.sock:/var/run/docker.sock",
      "/certs/client",
    ]

    shm_size = 2147483648      # 2 GB (25% of 8 GB RAM)
    cpus = "3.0"               # 3 of 4 cores (reserve 1 for OS & runner)
    memory = "6g"              # 6 GB max per job
    memory_swap = "6g"
    memory_reservation = "4g"  # 4 GB soft limit
    network_mode = "bridge"
    pull_policy = ["if-not-present"]
    helper_image = "gitlab/gitlab-runner-helper:ubuntu-x86_64-v18.9.0"

    environment = [
      "DOCKER_DRIVER=overlay2",
      "DOCKER_TLS_CERTDIR=/certs",
      "DOCKER_BUILDKIT=1",
      "BUILDKIT_INLINE_CACHE=1",
      "GOPATH=/root/go",
      "GOCACHE=/root/.cache/go-build",
      "GOMODCACHE=/root/go/pkg/mod",
      "COMPOSER_CACHE_DIR=/root/.composer/cache",
      "NPM_CONFIG_CACHE=/root/.npm",
    ]

  [runners.docker.tmpfs]
    "/tmp" = "rw,noexec,nosuid,size=512m"
    "/run" = "rw,noexec,nosuid,size=256m"
```

#### Variant B — 8 CPU / 16 GB RAM

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
      "/srv/gitlab-runner/cache/composer:/root/.composer/cache:rw",
      "/srv/gitlab-runner/cache/npm:/root/.npm:rw",
      "/srv/gitlab-runner/cache/yarn:/root/.yarn:rw",
      "/srv/gitlab-runner/cache/pnpm:/root/.local/share/pnpm/store:rw",
      "/srv/gitlab-runner/cache/go/pkg:/root/go/pkg:rw",
      "/srv/gitlab-runner/cache/go/build:/root/.cache/go-build:rw",
      "/srv/docker-buildkit-cache:/buildkit-cache:rw",
      "/var/run/docker.sock:/var/run/docker.sock",
      "/certs/client",
    ]

    shm_size = 4294967296      # 4 GB (25% of 16 GB RAM)
    cpus = "6.0"               # 6 of 8 cores (reserve 2 for OS & runner)
    memory = "12g"             # 12 GB max per job
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
      "GOPATH=/root/go",
      "GOCACHE=/root/.cache/go-build",
      "GOMODCACHE=/root/go/pkg/mod",
      "COMPOSER_CACHE_DIR=/root/.composer/cache",
      "NPM_CONFIG_CACHE=/root/.npm",
    ]

  [runners.docker.tmpfs]
    "/tmp" = "rw,noexec,nosuid,size=1024m"
    "/run" = "rw,noexec,nosuid,size=512m"
```

---

### `docker-compose.yml`

> Save to `~/glrunner/docker-compose.yml`

#### Variant A — 4 CPU / 8 GB RAM

```yaml
services:
  gitlab-runner:
    image: gitlab/gitlab-runner:ubuntu-v18.9.0
    container_name: GL-Runner-Jakarta01
    restart: unless-stopped
    privileged: true
    cpus: "3.5"
    mem_limit: "7g"
    mem_reservation: "5g"
    shm_size: "2g"
    volumes:
      - /srv/gitlab-runner/config:/etc/gitlab-runner
      - /var/run/docker.sock:/var/run/docker.sock
      - /srv/gitlab-runner/cache/composer:/root/.composer/cache
      - /srv/gitlab-runner/cache/npm:/root/.npm
      - /srv/gitlab-runner/cache/yarn:/root/.yarn
      - /srv/gitlab-runner/cache/pnpm:/root/.local/share/pnpm/store
      - /srv/gitlab-runner/cache/go/pkg:/root/go/pkg
      - /srv/gitlab-runner/cache/go/build:/root/.cache/go-build
      - /srv/docker-buildkit-cache:/buildkit-cache
      - /srv/gitlab-runner/cache:/cache
    environment:
      - DOCKER_HOST=unix:///var/run/docker.sock
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
    networks:
      - gitlab-runner-net

networks:
  gitlab-runner-net:
    driver: bridge
```

#### Variant B — 8 CPU / 16 GB RAM

```yaml
services:
  gitlab-runner:
    image: gitlab/gitlab-runner:ubuntu-v18.9.0
    container_name: GL-Runner-Jakarta01
    restart: unless-stopped
    privileged: true
    cpus: "7.0"
    mem_limit: "15g"
    mem_reservation: "10g"
    shm_size: "4g"
    volumes:
      - /srv/gitlab-runner/config:/etc/gitlab-runner
      - /var/run/docker.sock:/var/run/docker.sock
      - /srv/gitlab-runner/cache/composer:/root/.composer/cache
      - /srv/gitlab-runner/cache/npm:/root/.npm
      - /srv/gitlab-runner/cache/yarn:/root/.yarn
      - /srv/gitlab-runner/cache/pnpm:/root/.local/share/pnpm/store
      - /srv/gitlab-runner/cache/go/pkg:/root/go/pkg
      - /srv/gitlab-runner/cache/go/build:/root/.cache/go-build
      - /srv/docker-buildkit-cache:/buildkit-cache
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

### Key Parameters Comparison

| Parameter | Variant A (4C/8G) | Variant B (8C/16G) |
|---|---|---|
| `concurrent` | 8 | 16 |
| `request_concurrency` | 8 | 16 |
| `cpus` (job) | `3.0` | `6.0` |
| `memory` (job) | `6g` | `12g` |
| `memory_reservation` (job) | `4g` | `8g` |
| `shm_size` | 2 GB | 4 GB |
| `/tmp` tmpfs | 512 MB | 1 GB |
| `/run` tmpfs | 256 MB | 512 MB |
| `cpus` (compose) | `3.5` | `7.0` |
| `mem_limit` (compose) | `7g` | `15g` |
| `mem_reservation` (compose) | `5g` | `10g` |
| Log `max-size` | 50 MB | 100 MB |
| Log `max-file` | 5 | 10 |

---

## Cache Cleanup Script

> Save to `/srv/gitlab-runner/config/cleanup.sh` — identical for both variants.

```bash
#!/bin/bash
set -uo pipefail

LOG="/var/log/gl-runner-cleanup.log"
MAX_LOG_SIZE_MB=50

# Rotate log if it exceeds 50 MB
if [ -f "$LOG" ] && [ $(du -sm "$LOG" | awk '{print $1}') -gt $MAX_LOG_SIZE_MB ]; then
  mv "$LOG" "${LOG}.$(date +%Y%m%d-%H%M%S).old"
  ls -t "${LOG}".*.old 2>/dev/null | tail -n +6 | xargs rm -f
fi

echo "=== Cache Cleanup $(date) ===" >> $LOG

declare -A CACHE_DIRS=(
  ["Composer"]="/srv/gitlab-runner/cache/composer:2"
  ["npm"]="/srv/gitlab-runner/cache/npm:2"
  ["yarn"]="/srv/gitlab-runner/cache/yarn:1"
  ["pnpm"]="/srv/gitlab-runner/cache/pnpm:1"
  ["Go Module"]="/srv/gitlab-runner/cache/go/pkg:2"
  ["Go Build"]="/srv/gitlab-runner/cache/go/build:2"
)

for NAME in "${!CACHE_DIRS[@]}"; do
  IFS=":" read -r DIR MAX_GB <<< "${CACHE_DIRS[$NAME]}"

  if [ ! -d "$DIR" ]; then
    echo "$NAME: directory $DIR not found, skipping." >> $LOG
    continue
  fi

  # Remove files not accessed in the last 3 days
  find "$DIR" -atime +3 -type f -delete >> $LOG 2>&1
  find "$DIR" -empty -type d -delete >> $LOG 2>&1

  # Check size in MB for accuracy
  CURRENT_MB=$(du -sm "$DIR" 2>/dev/null | awk '{print $1}')
  MAX_MB=$(( MAX_GB * 1024 ))
  echo "$NAME: ${CURRENT_MB}MB / ${MAX_MB}MB (${MAX_GB}GB)" >> $LOG

  # Force remove oldest files if limit is exceeded
  if [ "${CURRENT_MB:-0}" -gt "$MAX_MB" ]; then
    echo "$NAME exceeded limit, removing oldest files..." >> $LOG
    find "$DIR" -type f -printf '%A+ %p\n' | sort | head -100 | awk '{print $2}' | \
      tee -a "$LOG" | xargs rm -f
  fi
done

# BuildKit — use docker buildx prune (not find -atime)
echo "Cleaning BuildKit cache..." >> $LOG
if [ -d "/srv/docker-buildkit-cache" ]; then
  docker buildx prune --filter "until=72h" --keep-storage=5gb -f >> $LOG 2>&1
else
  echo "BuildKit: directory not found, skipping." >> $LOG
fi

# Clean Docker resources
echo "Cleaning Docker resources..." >> $LOG
docker image prune -a --filter "until=72h" --force >> $LOG 2>&1
docker container prune --force >> $LOG 2>&1
docker volume prune --force >> $LOG 2>&1
docker network prune --force >> $LOG 2>&1

# Check /srv disk usage
DISK_USAGE=$(df -h /srv | awk 'NR==2 {print $5}')
DISK_USAGE_PCT=$(df /srv | awk 'NR==2 {gsub("%",""); print $5}')
echo "Disk usage /srv: ${DISK_USAGE}" >> $LOG

if [ "$DISK_USAGE_PCT" -gt 80 ]; then
  echo "⚠️  WARNING: Disk usage /srv ${DISK_USAGE}, exceeded 80%!" >> $LOG
fi

echo "=== Done $(date) ===" >> $LOG
echo "" >> $LOG
```

```bash
# Make the script executable
chmod +x /srv/gitlab-runner/config/cleanup.sh
```

---

## Crontab Schedule

The same for both variants:

```bash
sudo crontab -e
```

```bash
# ====================================
# GitLab Runner Cache Cleanup
# ====================================

# Full cleanup every day at 01:00
0 1 * * * /srv/gitlab-runner/config/cleanup.sh

# Emergency cleanup if /srv disk > 80% (check every 30 minutes)
*/30 * * * * df /srv | awk 'NR==2 {gsub("%",""); if($5>80) system("/srv/gitlab-runner/config/cleanup.sh")}'

# Docker image cleanup only every 12 hours (lightweight)
0 */12 * * * docker image prune -a --filter "until=72h" --force >> /var/log/gl-runner-cleanup.log 2>&1
```

> **Note:** The script is located at `/srv/gitlab-runner/config/cleanup.sh` on the host.

### Schedule Summary

| Schedule | Action |
|---|---|
| Every day at 01:00 | Full cleanup of all caches + Docker |
| Every 30 minutes | Check disk, emergency cleanup if /srv > 80% |
| Every 12 hours | Docker image cleanup only |

---

## Running the Runner

```bash
cd ~/glrunner

# Start
sudo docker compose up -d

# View logs
sudo docker compose logs -f

# Restart
sudo docker compose restart

# Stop
sudo docker compose down
```

---

## Verification & Monitoring

```bash
# Check container status
sudo docker ps | grep gitlab-runner

# Monitor cleanup log
tail -f /var/log/gl-runner-cleanup.log

# Check disk usage
df -h /srv

# Run cleanup manually
/srv/gitlab-runner/config/cleanup.sh

# View crontab
sudo crontab -l
```

---

## Example `.gitlab-ci.yml`

```yaml
# PHP — Composer
php-install:
  image: php:8.3
  tags: [install-autoscale]
  script:
    - composer install --no-interaction --prefer-dist
  # Cache auto-populated via volume /root/.composer/cache

# Node.js — npm
node-install:
  image: node:20-alpine
  tags: [install-autoscale]
  script:
    - npm ci
  # Cache auto-populated via volume /root/.npm

# Golang
go-build:
  image: golang:1.22
  tags: [build-autoscale]
  script:
    - go mod download
    - go build ./...
  # Cache auto-populated via volumes /root/go/pkg and /root/.cache/go-build

# Build Docker Image with BuildKit
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

---

> ⚠️ **Security Note:** Never store the GitLab Runner token (`glrt-...`) directly in configuration files committed to a repository. Use a secret management solution or a secure environment variable instead.
