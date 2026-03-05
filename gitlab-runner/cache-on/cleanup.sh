#!/bin/bash
set -uo pipefail

LOG="/var/log/gl-runner-cleanup.log"
MAX_LOG_SIZE_MB=50

# Rotasi log jika melebihi 50MB
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

# BuildKit — gunakan docker buildx prune, bukan find -atime
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

if [ "$DISK_USAGE_PCT" -gt 80 ]; then
  echo "⚠️  PERINGATAN: Disk usage /srv ${DISK_USAGE}, melebihi 80%!" >> $LOG
fi

echo "=== Selesai $(date) ===" >> $LOG
echo "" >> $LOG
