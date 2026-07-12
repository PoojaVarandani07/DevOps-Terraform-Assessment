#!/usr/bin/env bash
# =============================================================================
# scripts/restore.sh
# Restores a compressed PostgreSQL dump into a fresh local database.
# The target DB is dropped and recreated to guarantee a clean state.
#
# Usage:
#   ./scripts/restore.sh                                  # uses latest backup
#   ./scripts/restore.sh ./backups/backup_hoteldb_XYZ.sql.gz
#
# Prerequisites: docker compose up -d (postgres service must be healthy)
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-hoteldb}"
DB_USER="${DB_USER:-hoteluser}"
PGPASSWORD="${PGPASSWORD:-hotelpass}"
CONTAINER="${CONTAINER:-hotel_postgres}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}══════════════════════════════════════${NC}"; }

# ── Resolve backup file ───────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
  BACKUP_FILE="$1"
  info "Using specified backup: ${BACKUP_FILE}"
else
  LATEST_LINK="${BACKUP_DIR}/latest_${DB_NAME}.sql.gz"
  if [[ -L "${LATEST_LINK}" ]]; then
    BACKUP_FILE="${BACKUP_DIR}/$(readlink "${LATEST_LINK}")"
    info "No backup specified — using latest: ${BACKUP_FILE}"
  else
    error "No backup file specified and no latest symlink found."
    error "Run ./scripts/backup.sh first, or pass a backup file as an argument."
    exit 1
  fi
fi

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if [[ ! -f "${BACKUP_FILE}" ]]; then
  error "Backup file not found: ${BACKUP_FILE}"
  exit 1
fi

if ! command -v docker &>/dev/null; then
  error "Docker is not installed or not in PATH."
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  error "Container '${CONTAINER}' is not running."
  error "Start it with: docker compose up -d"
  exit 1
fi

# ── Safety prompt ─────────────────────────────────────────────────────────────
warn "This will DROP and recreate the database '${DB_NAME}'."
warn "All existing data will be permanently deleted."
echo -n "Type 'yes' to continue: "
read -r CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  info "Restore cancelled."
  exit 0
fi

export PGPASSWORD

# ── Step 1: Drop and recreate the target database ─────────────────────────────
section "Step 1 / 4 — Recreating database '${DB_NAME}'"

# Terminate existing connections first
docker exec \
  --env PGPASSWORD="${PGPASSWORD}" \
  "${CONTAINER}" \
  psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="postgres" \
    --no-password \
    --command="
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
    " > /dev/null

# Drop the database
docker exec \
  --env PGPASSWORD="${PGPASSWORD}" \
  "${CONTAINER}" \
  psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="postgres" \
    --no-password \
    --command="DROP DATABASE IF EXISTS \"${DB_NAME}\";" > /dev/null

# Recreate it
docker exec \
  --env PGPASSWORD="${PGPASSWORD}" \
  "${CONTAINER}" \
  psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="postgres" \
    --no-password \
    --command="CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";" > /dev/null

info "Database '${DB_NAME}' recreated."

# ── Step 2: Decompress and stream into psql ────────────────────────────────────
section "Step 2 / 4 — Restoring from $(basename "${BACKUP_FILE}")"

gunzip -c "${BACKUP_FILE}" | docker exec \
  --interactive \
  --env PGPASSWORD="${PGPASSWORD}" \
  "${CONTAINER}" \
  psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --no-password \
    --quiet

info "SQL restore complete."

# ── Step 3: Verify – row counts ───────────────────────────────────────────────
section "Step 3 / 4 — Verification"

info "Row counts after restore:"
docker exec \
  --env PGPASSWORD="${PGPASSWORD}" \
  "${CONTAINER}" \
  psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --no-password \
    --command="
      SELECT
        'hotel_bookings'  AS table_name, COUNT(*) AS rows FROM hotel_bookings
      UNION ALL
      SELECT
        'booking_events'  AS table_name, COUNT(*) AS rows FROM booking_events
      ORDER BY table_name;
    "

# ── Step 4: Run the target query as a smoke test ──────────────────────────────
section "Step 4 / 4 — Smoke test query"

info "Running optimised aggregation query (city=delhi, last 30 days):"
docker exec \
  --env PGPASSWORD="${PGPASSWORD}" \
  "${CONTAINER}" \
  psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --no-password \
    --command="
      SELECT
        org_id,
        status,
        COUNT(*)        AS booking_count,
        SUM(amount)     AS total_amount
      FROM hotel_bookings
      WHERE city       = 'delhi'
        AND created_at >= NOW() - INTERVAL '30 days'
      GROUP BY org_id, status
      ORDER BY org_id, status;
    "

info ""
info "✅ Restore verified successfully!"
info "   Backup file : ${BACKUP_FILE}"
info "   Database    : ${DB_NAME}"
