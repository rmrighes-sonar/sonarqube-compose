#!/usr/bin/env bash
# Restore a backup produced by ./scripts/backup.sh.
#
# Usage: ./scripts/restore.sh <backup-timestamp-dir>
#   e.g. ./scripts/restore.sh backups/20260914-113000
#
# WARNING: this overwrites the current database and SonarQube data volumes.
# Stop dependent services first; the db service must be running.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

BACKUP_DIR="${1:-}"
if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
  echo "Usage: $0 <backup-dir>" >&2
  echo "Available backups:" >&2
  ls -1 "${PROJECT_DIR}/backups" 2>/dev/null >&2 || true
  exit 1
fi
BACKUP_DIR="$(cd "${BACKUP_DIR}" && pwd)"

# Load POSTGRES_DB / POSTGRES_USER from .env
set -a
# shellcheck disable=SC1091
source ./.env
set +a

read -r -p "This will overwrite the current database and SonarQube data. Continue? [y/N] " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo "==> Ensuring db is up..."
docker compose up -d db
docker compose exec -T db sh -c 'until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do sleep 1; done'

if [[ -f "${BACKUP_DIR}/postgres.sql" ]]; then
  echo "==> Restoring Postgres database '${POSTGRES_DB}'..."
  docker compose exec -T db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c \
    "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
  docker compose exec -T db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    < "${BACKUP_DIR}/postgres.sql"
else
  echo "No postgres.sql found in ${BACKUP_DIR}, skipping database restore." >&2
fi

echo "==> Stopping sonarqube before restoring volumes..."
docker compose stop sonarqube

if [[ -f "${BACKUP_DIR}/sonarqube_data.tar.gz" ]]; then
  echo "==> Restoring sonarqube_data volume..."
  docker run --rm \
    -v sonarqube-local_sonarqube_data:/data \
    -v "${BACKUP_DIR}:/backup" \
    alpine:latest \
    sh -c "rm -rf /data/* && tar xzf /backup/sonarqube_data.tar.gz -C /data"
fi

if [[ -f "${BACKUP_DIR}/sonarqube_extensions.tar.gz" ]]; then
  echo "==> Restoring sonarqube_extensions volume..."
  docker run --rm \
    -v sonarqube-local_sonarqube_extensions:/data \
    -v "${BACKUP_DIR}:/backup" \
    alpine:latest \
    sh -c "rm -rf /data/* && tar xzf /backup/sonarqube_extensions.tar.gz -C /data"
fi

echo "==> Restore complete. Starting sonarqube..."
docker compose up -d sonarqube
