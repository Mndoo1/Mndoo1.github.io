#!/bin/bash
set -euo pipefail

BACKUP_DIR="/home/ec2-user/backups/mongodb"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/mongodump_${TIMESTAMP}"

MONGO_USER="${MONGO_ROOT_USER:-admin}"
MONGO_PASS="${MONGO_ROOT_PASS:-}"

if [ -z "$MONGO_PASS" ]; then
  echo "ERROR: MONGO_ROOT_PASS environment variable is not set."
  echo "Usage: MONGO_ROOT_USER=admin MONGO_ROOT_PASS=yourpass ./backup-mongodb.sh"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting MongoDB backup..."

docker exec mongodb mongodump \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase admin \
  --out "/tmp/mongodump_${TIMESTAMP}"

docker cp "mongodb:/tmp/mongodump_${TIMESTAMP}" "$BACKUP_FILE"

docker exec mongodb rm -rf "/tmp/mongodump_${TIMESTAMP}"

tar -czf "${BACKUP_FILE}.tar.gz" -C "$BACKUP_DIR" "mongodump_${TIMESTAMP}"
rm -rf "$BACKUP_FILE"

echo "[$(date)] Backup saved to ${BACKUP_FILE}.tar.gz"

echo "[$(date)] Removing backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "mongodump_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

echo "[$(date)] Backup completed successfully."
echo ""
echo "To restore, run:"
echo "  tar -xzf ${BACKUP_FILE}.tar.gz -C /tmp"
echo "  docker cp /tmp/mongodump_${TIMESTAMP} mongodb:/tmp/"
echo "  docker exec mongodb mongorestore --username admin --password YOUR_PASS --authenticationDatabase admin /tmp/mongodump_${TIMESTAMP}"
