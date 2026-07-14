#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

parse_common_flags "$@"

echo "INSTALL_AGENT"
echo "  dry-run: $DRY_RUN"
echo "  app: $APP_PATH"
echo "  version: $(app_version)"

if ! command -v swift >/dev/null 2>&1; then
  echo "  blocked: Swift toolchain not found" >&2
  exit 1
fi

if ((DRY_RUN)); then
  echo "[dry-run] build release executable"
  echo "[dry-run] stop the existing $APP_NAME process"
  package_app "$APP_PATH"
  echo "[dry-run] refresh an already installed privileged helper with one administrator prompt"
  echo "[dry-run] preserve existing settings and login-start registration; seed missing config files"
  echo "INSTALL_AGENT_DRY_RUN_OK"
  exit 0
fi

login_start_was_enabled=0
installed_login_maintenance_version="$(
  /usr/libexec/PlistBuddy -c 'Print :MacBootstrapLoginLaunchMaintenanceVersion' \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
)"
if [[ "$installed_login_maintenance_version" =~ ^[12]$ ]] \
  && [ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ] \
  && "$APP_PATH/Contents/MacOS/$APP_NAME" --login-launch-is-enabled >/dev/null 2>&1; then
  login_start_was_enabled=1
elif [ -f "$LEGACY_LOGIN_PLIST" ] \
  || launchctl print "gui/$(id -u)/$LEGACY_LOGIN_LABEL" >/dev/null 2>&1; then
  login_start_was_enabled=1
fi

"$ROOT_DIR/scripts/build.sh"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
for _ in {1..20}; do
  pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
  sleep 0.1
done
refresh_power_helper=0
if [ -e "$INSTALLED_HELPER_PATH" ] || [ -e "$INSTALLED_HELPER_PLIST" ]; then
  refresh_power_helper=1
fi
if [ -f "$APP_PATH/Contents/Library/LaunchDaemons/$HELPER_PLIST" ] \
  && [ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ] \
  && [ "$(/usr/libexec/PlistBuddy -c 'Print :MacBootstrapPowerHelperMaintenanceVersion' \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)" = "1" ]; then
  if ! "$APP_PATH/Contents/MacOS/$APP_NAME" --unregister-power-helper; then
    echo "  blocked: could not remove the legacy background helper" >&2
    exit 1
  fi
fi
if ((refresh_power_helper)) && [ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ]; then
  if ! "$APP_PATH/Contents/MacOS/$APP_NAME" --disable-power-helper; then
    echo "  blocked: could not safely restore normal sleep before updating" >&2
    exit 1
  fi
fi
package_app "$APP_PATH"
if ((login_start_was_enabled)); then
  if ! "$APP_PATH/Contents/MacOS/$APP_NAME" --refresh-login-launch; then
    echo "  blocked: could not migrate or refresh the native login item" >&2
    exit 1
  fi
fi
if ((refresh_power_helper)); then
  if ! "$APP_PATH/Contents/MacOS/$APP_NAME" --register-power-helper; then
    echo "  blocked: could not refresh the privileged sleep helper" >&2
    exit 1
  fi
fi
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/bootstrap.conf" ]; then
  cp "$ROOT_DIR/config/bootstrap.conf" "$CONFIG_DIR/bootstrap.conf"
fi
if [ ! -f "$CONFIG_DIR/hotkeys.conf" ]; then
  cp "$ROOT_DIR/config/hotkeys.conf" "$CONFIG_DIR/hotkeys.conf"
fi
rm -f "$EARLY_LEGACY_PLIST"

echo "INSTALL_AGENT_OK"
echo "  note: installed only; the app was not launched and no new feature was enabled"
echo "  login start: $([[ "$login_start_was_enabled" = "1" ]] && echo preserved || echo disabled)"
