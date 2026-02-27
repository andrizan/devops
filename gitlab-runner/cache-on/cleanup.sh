#!/bin/bash

LOG="/var/log/gl-runner-cleanup.log"
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
