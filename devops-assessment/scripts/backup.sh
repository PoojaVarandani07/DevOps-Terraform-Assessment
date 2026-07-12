#!/usr/bin/env bash
# =============================================================================
# scripts/backup.sh
# Compose database and stores it in the ./backups/ directory.
#
# Usage:
#   ./scripts/backup.sh                  # uses defaults
#   DB_NAME=mydb ./scripts/backup.sh     # override DB name
#
# Prerequisites: docker compose up -d (postgres service must be healthy)
# =============================================================================

set -euo pipefail

# ── Configuration (override via environment variables) ───────────────────────
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-hoteldb}"
DB_USER="${DB_USER:-hoteluser}"
PGPASSWORD="${PGPASSWORD:-hotelpass}"
CONTAINER="${CONTAINER:-hotel_postgres}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

# ── Timestamp ─────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/backup_${DB_NAME}_${TIMESTAMP}.sql.gz"
LATEST_LINK="${BACKUP_DIR}/latest_${DB_NAME}.sql.gz"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
info "Starting backup of database '${DB_NAME}'"

# Check Docker is available
if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH."
  exit 1
fi

# Check the postgres container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  error "Container '${CONTAINER}' is not running."
  error "Start it with: docker compose up -d"
  exit 1
fi

# Create the backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# ── Perform the backup ────────────────────────────────────────────────────────
info "Running pg_dump inside container '${CONTAINER}'..."

export PGPASSWORD

# pg_dump runs INSIDE the container so we don't need pg_dump locally.
# The output is piped through gzip on the host for compression.
docker exec \
  --env PGPASSWORD="${PGPASSWORD}" \
  "${CONTAINER}" \
  pg_dump \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --format=plain \
    --no-password \
    --verbose 2>/dev/null \
| gzip -9 > "${BACKUP_FILE}"

# Verify the file was created and is non-empty
if [[ ! -s "${BACKUP_FILE}" ]]; then
  error "Backup file is empty or was not created: ${BACKUP_FILE}"
  rm -f "${BACKUP_FILE}"
  exit 1
fi

# ── Create a "latest" symlink for easy restore ────────────────────────────────
ln -sf "$(basename "${BACKUP_FILE}")" "${LATEST_LINK}"

# ── Summary ───────────────────────────────────────────────────────────────────
BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
info "Backup completed successfully!"
info "  File  : ${BACKUP_FILE}"
info "  Size  : ${BACKUP_SIZE}"
info "  Latest: ${LATEST_LINK}"

# ── Optional: prune old backups (keep last 7) ─────────────────────────────────
KEEP=7
OLD_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name "backup_${DB_NAME}_*.sql.gz" | wc -l | tr -d ' ')
if (( OLD_COUNT > KEEP )); then
  warn "Pruning old backups (keeping ${KEEP} most recent)..."
  find "${BACKUP_DIR}" -maxdepth 1 -name "backup_${DB_NAME}_*.sql.gz" \
    | sort | head -n "-${KEEP}" | xargs rm -f
  info "Pruned $((OLD_COUNT - KEEP)) old backup(s)."
fi
