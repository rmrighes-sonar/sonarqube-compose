#!/usr/bin/env bash
# Back up the Postgres database and the sonarqube_data volume (plugins,
# extensions, Elasticsearch index metadata) into ./backups/<timestamp>/.
#
# Usage: ./scripts/backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# Load POSTGRES_DB / POSTGRES_USER from .env
set -a
# shellcheck disable=SC1091
source ./.env
set +a

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${PROJECT_DIR}/backups/${TIMESTAMP}"
mkdir -p "${OUT_DIR}"

echo "==> Backing up Postgres database '${POSTGRES_DB}'..."
docker compose exec -T db pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" \
  > "${OUT_DIR}/postgres.sql"

echo "==> Backing up sonarqube_data volume (plugins, extensions, indexes)..."
docker run --rm \
  -v sonarqube-local_sonarqube_data:/data:ro \
  -v "${OUT_DIR}:/backup" \
  alpine:latest \
  tar czf /backup/sonarqube_data.tar.gz -C /data .

echo "==> Backing up sonarqube_extensions volume (plugins)..."
docker run --rm \
  -v sonarqube-local_sonarqube_extensions:/data:ro \
  -v "${OUT_DIR}:/backup" \
  alpine:latest \
  tar czf /backup/sonarqube_extensions.tar.gz -C /data .

echo "==> Backup complete: ${OUT_DIR}"
