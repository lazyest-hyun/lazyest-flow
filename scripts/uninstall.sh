#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

parse_common_flags "$@"

echo "UNINSTALL_FLOW"
echo "  dry-run: $DRY_RUN"
echo "  app: $APP_PATH"

login_maintenance_version="$(
  /usr/libexec/PlistBuddy -c 'Print :MacBootstrapLoginLaunchMaintenanceVersion' \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
)"
legacy_login_registration_present=0
if [ -f "$LEGACY_LOGIN_PLIST" ] \
  || launchctl print "gui/$(id -u)/$LEGACY_LOGIN_LABEL" >/dev/null 2>&1; then
  legacy_login_registration_present=1
fi
if ((DRY_RUN)); then
  echo "[dry-run] disable and remove the login-start registration if present"
elif [ "$login_maintenance_version" = "2" ] \
  && [ -x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" ]; then
  if ! "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --disable-login-launch; then
    echo "  blocked: could not safely remove the login-start registration" >&2
    exit 1
  fi
elif [ "$login_maintenance_version" = "1" ] \
  && ((legacy_login_registration_present)) \
  && [ -x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" ]; then
  if ! "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --disable-login-launch; then
    echo "  blocked: could not safely remove the legacy login-start registration" >&2
    exit 1
  fi
elif ((legacy_login_registration_present)); then
  echo "  blocked: login-start registration exists but the Flow maintenance tool is missing" >&2
  exit 1
fi

run_cmd pkill -x "$APP_EXECUTABLE" || true
run_cmd pkill -x "$LEGACY_APP_NAME" || true
if ((!DRY_RUN)); then
  for _ in {1..20}; do
    if ! pgrep -x "$APP_EXECUTABLE" >/dev/null 2>&1 \
      && ! pgrep -x "$LEGACY_APP_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi
if ((DRY_RUN)); then
  echo "[dry-run] disable and remove the privileged sleep helper if present"
elif [ -x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" ]; then
  if ! "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --unregister-power-helper; then
    echo "  blocked: could not safely disable and remove the sleep helper" >&2
    exit 1
  fi
elif [ -e "$INSTALLED_HELPER_PATH" ] || [ -e "$INSTALLED_HELPER_PLIST" ]; then
  echo "  blocked: helper files exist but the signed Flow maintenance tool is missing" >&2
  exit 1
fi
if [ -d "$APP_PATH" ]; then
  run_cmd rm -rf "$APP_PATH"
fi
if [ -d "$LEGACY_APP_PATH" ]; then
  run_cmd rm -rf "$LEGACY_APP_PATH"
fi
for plist in "$LEGACY_LOGIN_PLIST" "$EARLY_LEGACY_PLIST"; do
  if [ -f "$plist" ]; then
    run_cmd rm -f "$plist"
  fi
done

echo "UNINSTALL_FLOW_OK"
echo "  note: user settings were preserved at $CONFIG_DIR"
