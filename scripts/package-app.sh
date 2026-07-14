#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if (($# != 1)); then
  echo "Usage: $0 APP_PATH" >&2
  exit 2
fi

if [ ! -x "$(release_binary)" ] || [ ! -x "$(release_helper_binary)" ]; then
  echo "Release binaries missing; run ./bootstrap.sh build first" >&2
  exit 1
fi

package_app "$1"
