#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <snapshot_id> <restore_directory>"
    echo "Example: $0 k8f21... /home/mastodon/restore_data"
    echo "Run 'kopia/kopia.sh snapshot restore --help' for options"
    exit 1
fi

SNAPSHOT_ID="$1"
RESTORE_PATH="$2"

if [ ! -d "$RESTORE_PATH" ]; then
    echo "Error: Restore directory '$RESTORE_PATH' does not exist or is not a directory."
    exit 1
fi

ABS_RESTORE_PATH=$(realpath "$RESTORE_PATH")
CONTAINER_RESTORE_PATH="/restore"

echo "Restoring snapshot '$SNAPSHOT_ID' to '$ABS_RESTORE_PATH'..."

docker run --rm \
  -e KOPIA_PASSWORD="{{ kopia_password }}" \
  -e KOPIA_LOG_DIR=/app/logs \
  -v "{{ root }}/kopia/config":/app/config \
  -v "{{ root }}/kopia/cache":/app/cache \
  -v "{{ root }}/kopia/rclone":/app/rclone \
  -v "{{ root }}/kopia/logs":/app/logs \
  -v "${ABS_RESTORE_PATH}":${CONTAINER_RESTORE_PATH} \
  "kopia/kopia:{{ kopia_version }}" \
  snapshot restore "${SNAPSHOT_ID}" "${CONTAINER_RESTORE_PATH}"

echo "Restore complete."
