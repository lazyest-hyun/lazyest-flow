#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LazyestFlow"
APP_BUNDLE="$ROOT_DIR/dist/Lazyest Flow.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *) echo "Usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
"$ROOT_DIR/bootstrap.sh" build
mkdir -p "$ROOT_DIR/dist"
"$ROOT_DIR/scripts/package-app.sh" "$APP_BUNDLE"

open_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Flow is still running; close it before starting this build." >&2
    return 1
  fi
  /usr/bin/open "$APP_BUNDLE"
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
    /usr/bin/log stream --info --style compact --predicate 'subsystem BEGINSWITH "com.lazyest.flow"'
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
