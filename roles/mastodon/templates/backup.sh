#!/usr/bin/env bash

set -eou pipefail

HEALTH_CHECKS_IO_URL="{{ health_checks_io_url }}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

if [[ -n "${HEALTH_CHECKS_IO_URL}" ]]; then
  curl -fsS -m 10 --retry 5 -o /dev/null "${HEALTH_CHECKS_IO_URL}/start"
fi

echo "Creating Postgres dump..."

ionice -c idle nice docker-compose exec -T db pg_dumpall -h db -U postgres -w > backup/mastodon.sql

echo "Done creating Postgres dump"
echo "Starting Kopia backup of the Postgres dump and Mastodon files/"

cd kopia

ionice -c idle nice docker run --rm -e KOPIA_PASSWORD="{{ kopia_password }}" -e KOPIA_LOG_DIR=/app/logs \
  -v "$(pwd)"/config:/app/config \
  -v "$(pwd)"/cache:/app/cache \
  -v "$(pwd)"/rclone:/app/rclone \
  -v "$(pwd)"/logs:/app/logs \
  -v "{{ root }}":/backup-src \
  "kopia/kopia:{{ kopia_version }}" \
  snapshot create --log-level=warning --no-progress \
  /backup-src/backup /backup-src/files 2>&1 # docker pulls print to stderr causing cronic to think it's failing

echo "Done Kopia backup"

if [[ -n "${HEALTH_CHECKS_IO_URL}" ]]; then
  curl -fsS -m 10 --retry 5 -o /dev/null "${HEALTH_CHECKS_IO_URL}"
fi
