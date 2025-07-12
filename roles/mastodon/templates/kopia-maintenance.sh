#!/usr/bin/env bash

set -eou pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

./kopia.sh maintenance run --full 2>&1
