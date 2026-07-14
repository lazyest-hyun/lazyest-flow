#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

parse_common_flags "$@"

echo "BUILD_AGENT"
echo "  dry-run: $DRY_RUN"
echo "  package: $ROOT_DIR"

if ! command -v swift >/dev/null 2>&1; then
  echo "  blocked: Swift toolchain not found" >&2
  exit 1
fi

if ((DRY_RUN)); then
  echo "[dry-run] swift build --package-path $ROOT_DIR -c release --product $APP_NAME"
  echo "[dry-run] swift build --package-path $ROOT_DIR -c release --product $HELPER_NAME"
  exit 0
fi

if ! swift build --package-path "$ROOT_DIR" -c release --product "$APP_NAME" \
  || ! swift build --package-path "$ROOT_DIR" -c release --product "$HELPER_NAME"; then
  echo "  blocked: Swift and the active macOS SDK must come from a compatible Xcode or Command Line Tools installation" >&2
  exit 1
fi
