#!/usr/bin/env bash

set -eou pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

# pull first, so it's not written to stderr during run
docker pull "kopia/kopia:{{ kopia_version }}" >& /dev/null

ionice -c idle nice docker run --rm -e KOPIA_PASSWORD="{{ kopia_password }}" -e KOPIA_LOG_DIR=/app/logs \
  -v "$(pwd)"/config:/app/config \
  -v "$(pwd)"/cache:/app/cache \
  -v "$(pwd)"/rclone:/app/rclone \
  -v "$(pwd)"/logs:/app/logs \
  -v "{{ root }}":/backup-src \
  "kopia/kopia:{{ kopia_version }}" --log-level=info --no-progress "$@"

