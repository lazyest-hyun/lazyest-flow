#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNING_IDENTITY="${LAZYEST_CODESIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${LAZYEST_INSTALLER_IDENTITY:-}"
TEAM_ID="${LAZYEST_TEAM_ID:-}"
NOTARY_PROFILE="${LAZYEST_NOTARY_PROFILE:-}"
PREFLIGHT_ONLY=0

if [ "${1:-}" = "--preflight" ]; then
  PREFLIGHT_ONLY=1
elif (($#)); then
  echo "Usage: $0 [--preflight]" >&2
  exit 2
fi

require_value() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "blocked: set $name in the shell environment" >&2
    exit 1
  fi
}

staple_with_retry() {
  local target="$1"
  local attempt
  for attempt in 1 2 3; do
    if xcrun stapler staple "$target"; then
      return
    fi
    if ((attempt < 3)); then
      echo "warning: stapler attempt $attempt failed; retrying" >&2
      sleep 2
    fi
  done
  return 1
}

require_value LAZYEST_CODESIGN_IDENTITY "$SIGNING_IDENTITY"
require_value LAZYEST_INSTALLER_IDENTITY "$INSTALLER_IDENTITY"
require_value LAZYEST_TEAM_ID "$TEAM_ID"
require_value LAZYEST_NOTARY_PROFILE "$NOTARY_PROFILE"

if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "blocked: LAZYEST_CODESIGN_IDENTITY must be a Developer ID Application identity" >&2
  exit 1
fi
if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null; then
  echo "blocked: Developer ID signing identity is not available in the Keychain" >&2
  exit 1
fi
if [[ "$INSTALLER_IDENTITY" != Developer\ ID\ Installer:*"$TEAM_ID)" ]]; then
  echo "blocked: LAZYEST_INSTALLER_IDENTITY must be a Developer ID Installer identity for LAZYEST_TEAM_ID" >&2
  exit 1
fi
if ! security find-identity -v -p basic 2>/dev/null | grep -F "\"$INSTALLER_IDENTITY\"" >/dev/null; then
  echo "blocked: Developer ID Installer identity is not available in the Keychain" >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "blocked: notarization Keychain profile is missing or invalid" >&2
  exit 1
fi

echo "PREFLIGHT_OK"
((PREFLIGHT_ONLY)) && exit 0

VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/Lazyest Flow.app"
ZIP_NAME="Lazyest-Flow-$VERSION-macOS.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
PKG_NAME="Lazyest-Flow-$VERSION-macOS.pkg"
PKG_PATH="$DIST_DIR/$PKG_NAME"

rm -rf "$APP_PATH" "$ZIP_PATH" "$ZIP_PATH.sha256" "$PKG_PATH" "$PKG_PATH.sha256"
"$SCRIPT_DIR/build.sh"
MAC_BOOTSTRAP_AGENT_CODESIGN_IDENTITY="$SIGNING_IDENTITY" \
  "$SCRIPT_DIR/package-app.sh" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ACTUAL_TEAM_ID="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ "$ACTUAL_TEAM_ID" != "$TEAM_ID" ]; then
  echo "blocked: signed app TeamIdentifier does not match LAZYEST_TEAM_ID" >&2
  exit 1
fi

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
staple_with_retry "$APP_PATH"
if ! xcrun stapler validate "$APP_PATH"; then
  echo "warning: unable to independently validate the stapled ticket from this Mac; continuing to the required Gatekeeper assessment" >&2
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

rm -f "$ZIP_PATH"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Contents/Info.plist")"
pkgbuild \
  --component "$APP_PATH" \
  --install-location "/Applications" \
  --identifier "$BUNDLE_ID.pkg" \
  --version "$VERSION" \
  --sign "$INSTALLER_IDENTITY" \
  "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH" >/dev/null
xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
staple_with_retry "$PKG_PATH"
if ! xcrun stapler validate "$PKG_PATH"; then
  echo "warning: unable to independently validate the PKG ticket from this Mac; continuing to the required Installer Gatekeeper assessment" >&2
fi
spctl --assess --type install --verbose=4 "$PKG_PATH"
(cd "$DIST_DIR" && shasum -a 256 "$PKG_NAME" >"$PKG_NAME.sha256")
echo "RELEASE_ARTIFACT_READY: $PKG_PATH"
