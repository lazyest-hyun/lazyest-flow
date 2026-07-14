#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./bootstrap.sh help
  ./bootstrap.sh version
  ./bootstrap.sh audit
  ./bootstrap.sh build [--dry-run]
  ./bootstrap.sh install [--dry-run]
  ./bootstrap.sh uninstall [--dry-run]

Commands:
  help        Show this help.
  version     Print the application version.
  audit       Read-only source, app, process, and config summary.
  build       Build the release Swift executable.
  install     Build and install /Applications/MacBootstrapAgent.app.
  uninstall   Remove the app while preserving user settings.
EOF
}

command_name="${1:-help}"
if (($#)); then
  shift
fi

case "$command_name" in
  help|-h|--help)
    usage
    ;;
  version)
    tr -d '[:space:]' <"$ROOT_DIR/VERSION"
    printf '\n'
    ;;
  audit)
    exec "$ROOT_DIR/scripts/audit.sh" "$@"
    ;;
  build)
    exec "$ROOT_DIR/scripts/build.sh" "$@"
    ;;
  install)
    exec "$ROOT_DIR/scripts/install.sh" "$@"
    ;;
  uninstall)
    exec "$ROOT_DIR/scripts/uninstall.sh" "$@"
    ;;
  *)
    echo "Unknown command: $command_name" >&2
    usage >&2
    exit 2
    ;;
esac
