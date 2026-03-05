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
