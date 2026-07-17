#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

parse_common_flags "$@"

echo "INSTALL_FLOW"
echo "  dry-run: $DRY_RUN"
echo "  app: $APP_PATH"
echo "  version: $(app_version)"

if ! command -v swift >/dev/null 2>&1; then
  echo "  blocked: Swift toolchain not found" >&2
  exit 1
fi

if ((DRY_RUN)); then
  echo "[dry-run] build release executable"
  echo "[dry-run] stop the existing $APP_EXECUTABLE or $LEGACY_APP_NAME process"
  package_app "$APP_PATH"
  echo "[dry-run] refresh an already installed privileged helper with one administrator prompt"
  echo "[dry-run] preserve existing settings and login-start registration; seed missing config files"
  echo "INSTALL_FLOW_DRY_RUN_OK"
  exit 0
fi

login_start_was_enabled=0
installed_app_path="$APP_PATH"
if [ ! -d "$installed_app_path" ] && [ -d "$LEGACY_APP_PATH" ]; then
  installed_app_path="$LEGACY_APP_PATH"
fi
installed_executable_name="$APP_EXECUTABLE"
if [ "$installed_app_path" = "$LEGACY_APP_PATH" ]; then
  installed_executable_name="$LEGACY_APP_NAME"
fi
installed_executable="$installed_app_path/Contents/MacOS/$installed_executable_name"
installed_login_maintenance_version="$(
  /usr/libexec/PlistBuddy -c 'Print :MacBootstrapLoginLaunchMaintenanceVersion' \
    "$installed_app_path/Contents/Info.plist" 2>/dev/null || true
)"
if [[ "$installed_login_maintenance_version" =~ ^[12]$ ]] \
  && [ -x "$installed_executable" ] \
  && "$installed_executable" --login-launch-is-enabled >/dev/null 2>&1; then
  login_start_was_enabled=1
elif [ -f "$LEGACY_LOGIN_PLIST" ] \
  || launchctl print "gui/$(id -u)/$LEGACY_LOGIN_LABEL" >/dev/null 2>&1; then
  login_start_was_enabled=1
fi

"$ROOT_DIR/scripts/build.sh"
pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
pkill -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true
for _ in {1..20}; do
  if ! pgrep -x "$APP_EXECUTABLE" >/dev/null 2>&1 \
    && ! pgrep -x "$LEGACY_APP_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
refresh_power_helper=0
if [ -e "$INSTALLED_HELPER_PATH" ] || [ -e "$INSTALLED_HELPER_PLIST" ]; then
  refresh_power_helper=1
fi
if [ -f "$installed_app_path/Contents/Library/LaunchDaemons/$HELPER_PLIST" ] \
  && [ -x "$installed_executable" ]; then
  helper_maintenance_version="$(/usr/libexec/PlistBuddy -c 'Print :LazyestPowerHelperMaintenanceVersion' \
    "$installed_app_path/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Print :MacBootstrapPowerHelperMaintenanceVersion' \
    "$installed_app_path/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$helper_maintenance_version" = "1" ] && ! "$installed_executable" --unregister-power-helper; then
    echo "  blocked: could not remove the legacy background helper" >&2
    exit 1
  fi
fi
if ((refresh_power_helper)) && [ -x "$installed_executable" ]; then
  if ! "$installed_executable" --disable-power-helper; then
    echo "  blocked: could not safely restore normal sleep before updating" >&2
    exit 1
  fi
fi
package_app "$APP_PATH"
if [ -d "$LEGACY_APP_PATH" ]; then
  rm -rf "$LEGACY_APP_PATH"
fi
if ((login_start_was_enabled)); then
  if ! "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --refresh-login-launch; then
    echo "  blocked: could not migrate or refresh the native login item" >&2
    exit 1
  fi
fi
if ((refresh_power_helper)); then
  if ! "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --register-power-helper; then
    echo "  blocked: could not refresh the privileged sleep helper" >&2
    exit 1
  fi
fi
if [ ! -d "$CONFIG_DIR" ] && [ -d "$LEGACY_CONFIG_DIR" ]; then
  cp -R "$LEGACY_CONFIG_DIR" "$CONFIG_DIR"
fi
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/bootstrap.conf" ]; then
  cp "$ROOT_DIR/config/bootstrap.conf" "$CONFIG_DIR/bootstrap.conf"
fi
if [ ! -f "$CONFIG_DIR/hotkeys.conf" ]; then
  cp "$ROOT_DIR/config/hotkeys.conf" "$CONFIG_DIR/hotkeys.conf"
fi
rm -f "$EARLY_LEGACY_PLIST"

echo "INSTALL_FLOW_OK"
echo "  note: installed only; the app was not launched and no new feature was enabled"
echo "  login start: $([[ "$login_start_was_enabled" = "1" ]] && echo preserved || echo disabled)"
