#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNING_IDENTITY="${LAZYEST_CODESIGN_IDENTITY:-}"
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

require_value LAZYEST_CODESIGN_IDENTITY "$SIGNING_IDENTITY"
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

rm -rf "$APP_PATH" "$ZIP_PATH" "$ZIP_PATH.sha256"
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
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
(cd "$DIST_DIR" && shasum -a 256 "$ZIP_NAME" >"$ZIP_NAME.sha256")
echo "RELEASE_ARTIFACT_READY: $ZIP_PATH"
