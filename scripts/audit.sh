#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

echo "LAZYEST_FLOW_AUDIT_OK"
echo "  source: $ROOT_DIR"
echo "  version: $(app_version)"
echo "  swift: $(command -v swift >/dev/null 2>&1 && echo present || echo missing)"
echo "  app: $([ -d "$APP_PATH" ] && echo installed || echo missing)"
echo "  process: $(pgrep -x "$APP_EXECUTABLE" >/dev/null 2>&1 && echo running || echo stopped)"
login_maintenance_version="$(
  /usr/libexec/PlistBuddy -c 'Print :MacBootstrapLoginLaunchMaintenanceVersion' \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
)"
if [ "$login_maintenance_version" = "2" ] \
  && [ -x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" ]; then
  login_status="$(
    "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --login-launch-status 2>/dev/null \
      || echo needs-repair
  )"
  echo "  login start: $login_status"
elif [ "$login_maintenance_version" = "1" ] \
  && [ -x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" ] \
  && "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" --login-launch-is-enabled >/dev/null 2>&1; then
  echo "  login start: enabled"
elif [ -f "$LEGACY_LOGIN_PLIST" ] \
  || launchctl print "gui/$(id -u)/$LEGACY_LOGIN_LABEL" >/dev/null 2>&1; then
  echo "  login start: needs repair"
else
  echo "  login start: disabled"
fi
echo "  config: $([ -d "$CONFIG_DIR" ] && echo present || echo missing)"
echo "  hotkeys:"
if [ -f "$CONFIG_DIR/hotkeys.conf" ]; then
  awk -F'|' '/^[[:space:]]*toggle-app\|/ { count += 1 } END { printf "    %d configured\n", count + 0 }' "$CONFIG_DIR/hotkeys.conf"
else
  echo "    0 configured"
fi
