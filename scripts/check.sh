#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"
swift run LazyestCoreChecks
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/lazyest-flow-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -D LAZYEST_LOCK_TESTING \
  Sources/LazyestCore/PowerHelperProtocol.swift \
  Checks/PowerLockChecks/main.swift -o "$check_dir/power-lock-checks"
"$check_dir/power-lock-checks"
