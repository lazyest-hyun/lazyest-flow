#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LazyestFlow"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
"$ROOT_DIR/bootstrap.sh" build
mkdir -p "$ROOT_DIR/dist"
"$ROOT_DIR/scripts/package-app.sh" "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.estaid.mac-bootstrap-agent"'
    ;;
  --verify|verify)
    open_app
    for _ in 1 2 3 4 5; do
      pgrep -x "$APP_NAME" >/dev/null 2>&1 && exit 0
      sleep 0.2
    done
    echo "$APP_NAME did not start" >&2
    exit 1
    ;;
  *)
    echo "Usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
