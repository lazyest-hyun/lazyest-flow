#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Lazyest Flow"
APP_EXECUTABLE="LazyestFlow"
LEGACY_APP_NAME="MacBootstrapAgent"
BUNDLE_ID="com.estaid.mac-bootstrap-agent"
HELPER_NAME="LazyestPowerHelper"
HELPER_LABEL="$BUNDLE_ID.power-helper"
HELPER_PLIST="$HELPER_LABEL.plist"
INSTALLED_HELPER_PATH="/Library/PrivilegedHelperTools/$HELPER_LABEL"
INSTALLED_HELPER_PLIST="/Library/LaunchDaemons/$HELPER_PLIST"
APP_PATH="/Applications/$APP_NAME.app"
CONFIG_DIR="$HOME/Library/Application Support/$APP_NAME"
LEGACY_APP_PATH="/Applications/$LEGACY_APP_NAME.app"
LEGACY_CONFIG_DIR="$HOME/Library/Application Support/$LEGACY_APP_NAME"
LEGACY_LOGIN_LABEL="$BUNDLE_ID.login"
LEGACY_LOGIN_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LOGIN_LABEL.plist"
EARLY_LEGACY_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
DRY_RUN=0

parse_common_flags() {
  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 2
        ;;
    esac
    shift
  done
}

run_cmd() {
  if ((DRY_RUN)); then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

app_version() {
  local version
  version="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid semantic version: $version" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

release_binary() {
  printf '%s\n' "$ROOT_DIR/.build/release/$APP_EXECUTABLE"
}

release_helper_binary() {
  printf '%s\n' "$ROOT_DIR/.build/release/$HELPER_NAME"
}

codesign_identity() {
  printf '%s\n' "${MAC_BOOTSTRAP_AGENT_CODESIGN_IDENTITY:-MacBootstrap Local Code Signing}"
}

codesign_identity_available() {
  local identity
  identity="$(codesign_identity)"
  [ -n "$identity" ] || return 1
  security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$identity\"" >/dev/null
}

sign_app() {
  local app="$1"
  local helper="$app/Contents/MacOS/$HELPER_NAME"
  if codesign_identity_available; then
    local identity
    identity="$(codesign_identity)"
    echo "  codesign: $identity"
    if codesign --force --options runtime --sign "$identity" "$helper" \
      && codesign --force --options runtime --sign "$identity" "$app"; then
      return
    fi
    echo "  warning: stable codesign failed; using ad-hoc signing"
  else
    echo "  codesign: ad-hoc"
  fi
  codesign --force --options runtime --timestamp=none --sign - "$helper"
  codesign --force --options runtime --timestamp=none --sign - "$app"
}

validate_app_path() {
  case "$1" in
    "$APP_PATH"|"$ROOT_DIR/dist/$APP_NAME.app")
      ;;
    *)
      echo "Refusing to replace unexpected app path: $1" >&2
      return 1
      ;;
  esac
}

package_app() {
  local app="$1"
  local binary
  local helper_binary
  local version
  binary="$(release_binary)"
  helper_binary="$(release_helper_binary)"
  version="$(app_version)"
  validate_app_path "$app"

  if ((DRY_RUN)); then
    echo "[dry-run] package $binary and $helper_binary as $app"
    return
  fi

  rm -rf "$app"
  mkdir -p \
    "$app/Contents/MacOS" \
    "$app/Contents/Resources"
  cp "$binary" "$app/Contents/MacOS/$APP_EXECUTABLE"
  cp "$helper_binary" "$app/Contents/MacOS/$HELPER_NAME"
  chmod +x "$app/Contents/MacOS/$APP_EXECUTABLE"
  chmod +x "$app/Contents/MacOS/$HELPER_NAME"
  cp "$ROOT_DIR/Assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$version</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LazyestPowerHelperMaintenanceVersion</key>
  <integer>2</integer>
  <key>MacBootstrapLoginLaunchMaintenanceVersion</key>
  <integer>2</integer>
</dict>
</plist>
PLIST
  printf 'APPL????' >"$app/Contents/PkgInfo"
  plutil -lint "$app/Contents/Info.plist" >/dev/null
  sign_app "$app"
}
