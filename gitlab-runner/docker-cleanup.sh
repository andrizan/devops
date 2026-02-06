#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOGFILE="/home/ebelanja/cleanup/docker-cleanup-$(date +%F).log"
VOLUME_RETENTION_DAYS=3
IMAGE_RETENTION_DAYS=14
LOG_RETENTION_DAYS=14
CACHE_RETENTION_DAYS=14
CACHE_DIR="/cache"

# =========================================================================
# Cara Setup Crontab (jalankan sebagai root):
# sudo crontab -e
# Tambahkan baris berikut (jalankan setiap hari jam 3 pagi):
# 0 3 * * * /home/ebelanja/cleanup/docker-cleanup.sh
#
# Pastikan script executable:
# sudo chmod +x /home/ebelanja/cleanup/docker-cleanup.sh
#==========================================================================

echo "=== Docker Cleanup $(date) ===" >> "$LOGFILE"

# Hapus file log lama yang lebih dari LOG_RETENTION_DAYS
echo "Menghapus file log lama..." >> "$LOGFILE"
find /home/ebelanja/cleanup/ -name "docker-cleanup-*.log" -type f -mtime +${LOG_RETENTION_DAYS} -exec rm -f {} \; >> "$LOGFILE" 2>&1
if [ $? -eq 0 ]; then
  echo "Berhasil menghapus file log yang lebih dari ${LOG_RETENTION_DAYS} hari" >> "$LOGFILE"
else
  echo "Gagal menghapus file log lama" >> "$LOGFILE"
fi

# Hapus file cache lama yang lebih dari CACHE_RETENTION_DAYS
echo "Menghapus file cache lama..." >> "$LOGFILE"
if [ -d "$CACHE_DIR" ]; then
  # Hapus file dan folder yang lebih tua dari CACHE_RETENTION_DAYS
  find "$CACHE_DIR" -type f -mtime +${CACHE_RETENTION_DAYS} -exec rm -f {} \; >> "$LOGFILE" 2>&1
  find "$CACHE_DIR" -type d -empty -delete >> "$LOGFILE" 2>&1

  if [ $? -eq 0 ]; then
    echo "Berhasil menghapus file cache yang lebih dari ${CACHE_RETENTION_DAYS} hari" >> "$LOGFILE"
  else
    echo "Gagal menghapus file cache lama" >> "$LOGFILE"
  fi
else
  echo "Direktori cache tidak ditemukan: $CACHE_DIR" >> "$LOGFILE"
fi

# Prune volume yang tidak terpakai
echo "Menjalankan docker volume prune..." >> "$LOGFILE"
sudo docker volume prune -f >> "$LOGFILE" 2>&1

# Hapus volume lama yang tidak digunakan
echo "Memeriksa volume lama..." >> "$LOGFILE"
for volume in $(sudo docker volume ls -q); do
  # Periksa apakah volume sedang digunakan oleh container
  in_use=$(sudo docker ps -a --filter volume="$volume" --format '{{.ID}}' | wc -l)

  if [ "$in_use" -eq 0 ]; then
    # Ambil informasi CreatedAt
    created_at=$(sudo docker volume inspect "$volume" --format '{{.CreatedAt}}' 2>/dev/null)

    if [ -z "$created_at" ]; then
      echo "Gagal mendapatkan informasi untuk volume: $volume" >> "$LOGFILE"
      continue
    fi

    # Konversi tanggal (handle format ISO 8601)
    created_epoch=$(date -d "${created_at}" +%s 2>/dev/null)

    if [ $? -ne 0 ]; then
      echo "Gagal parsing tanggal untuk volume: $volume ($created_at)" >> "$LOGFILE"
      continue
    fi

    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - created_epoch) / 86400 ))

    if [ "$age_days" -gt "$VOLUME_RETENTION_DAYS" ]; then
      echo "Menghapus volume lama: $volume (umur: $age_days hari)" >> "$LOGFILE"
      sudo docker volume rm "$volume" >> "$LOGFILE" 2>&1

      if [ $? -eq 0 ]; then
        echo "Berhasil menghapus volume: $volume" >> "$LOGFILE"
      else
        echo "Gagal menghapus volume: $volume" >> "$LOGFILE"
      fi
    else
      echo "Volume $volume masih dalam masa retensi ($age_days hari)" >> "$LOGFILE"
    fi
  else
    echo "Volume $volume masih digunakan oleh $in_use container" >> "$LOGFILE"
  fi
done

# Prune image yang tidak terpakai (dangling)
echo "Menjalankan docker image prune..." >> "$LOGFILE"
sudo docker image prune -f >> "$LOGFILE" 2>&1

# Hapus image lama yang tidak digunakan
echo "Memeriksa image lama..." >> "$LOGFILE"
for image_id in $(sudo docker images --format '{{.ID}}'); do
  # Periksa apakah image sedang digunakan oleh container
  in_use=$(sudo docker ps -a --filter ancestor="$image_id" --format '{{.ID}}' | wc -l)

  if [ "$in_use" -eq 0 ]; then
    # Ambil informasi image
    created_at=$(sudo docker image inspect "$image_id" --format '{{.Created}}' 2>/dev/null)
    image_name=$(sudo docker image inspect "$image_id" --format '{{index .RepoTags 0}}' 2>/dev/null)

    # Jika image tidak memiliki tag, gunakan ID
    if [ -z "$image_name" ] || [ "$image_name" == "<none>" ]; then
      image_name="$image_id"
    fi

    if [ -z "$created_at" ]; then
      echo "Gagal mendapatkan informasi untuk image: $image_name" >> "$LOGFILE"
      continue
    fi

    # Konversi tanggal
    created_epoch=$(date -d "${created_at}" +%s 2>/dev/null)

    if [ $? -ne 0 ]; then
      echo "Gagal parsing tanggal untuk image: $image_name ($created_at)" >> "$LOGFILE"
      continue
    fi

    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - created_epoch) / 86400 ))

    if [ "$age_days" -gt "$IMAGE_RETENTION_DAYS" ]; then
      echo "Menghapus image lama: $image_name (umur: $age_days hari)" >> "$LOGFILE"
      sudo docker image rm "$image_id" >> "$LOGFILE" 2>&1

      if [ $? -eq 0 ]; then
        echo "Berhasil menghapus image: $image_name" >> "$LOGFILE"
      else
        echo "Gagal menghapus image: $image_name" >> "$LOGFILE"
      fi
    else
      echo "Image $image_name masih dalam masa retensi ($age_days hari)" >> "$LOGFILE"
    fi
  else
    image_name=$(sudo docker image inspect "$image_id" --format '{{index .RepoTags 0}}' 2>/dev/null)
    if [ -z "$image_name" ]; then
      image_name="$image_id"
    fi
    echo "Image $image_name masih digunakan oleh $in_use container" >> "$LOGFILE"
  fi
done

echo "=== Cleanup selesai $(date) ===" >> "$LOGFILE"
echo "" >> "$LOGFILE"
