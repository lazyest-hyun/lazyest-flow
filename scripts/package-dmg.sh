#!/bin/bash
# Package a verified Lazyest app without requiring an Installer certificate.
set -euo pipefail
APP="${1:-}"
OUTPUT="${2:-}"
IDENTITY="${LAZYEST_CODESIGN_IDENTITY:-}"
PROFILE="${LAZYEST_NOTARY_PROFILE:-}"
fail() { echo "error: $*" >&2; exit 64; }
[[ $# -eq 2 && -d "$APP/Contents" && "$OUTPUT" == /*.dmg ]] || fail "Usage: package-dmg.sh /absolute/Lazyest.app /absolute/output.dmg"
[[ "$IDENTITY" == "Developer ID Application:"* && -n "$PROFILE" ]] || fail "Set LAZYEST_CODESIGN_IDENTITY and LAZYEST_NOTARY_PROFILE."
codesign --verify --deep --strict "$APP"
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Authority=$IDENTITY"* && "$SIGNATURE" == *"runtime"* ]] || fail "App must use the requested Developer ID with Hardened Runtime."
NAME="$(plutil -extract CFBundleName raw -o - "$APP/Contents/Info.plist")"
[[ "$NAME" == Lazyest* ]] || fail "Expected a Lazyest app."
mkdir -p "$(dirname "$OUTPUT")"
TEMP="$(mktemp -d /tmp/lazyest-dmg.XXXXXX)"
trap 'rm -rf -- "$TEMP"' EXIT
# Submit the app as well as its container so drag installation works offline.
ditto -c -k --keepParent "$APP" "$TEMP/app.zip"
xcrun notarytool submit "$TEMP/app.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
mkdir "$TEMP/root"
ditto "$APP" "$TEMP/root/$(basename "$APP")"
ln -s /Applications "$TEMP/root/Applications"
hdiutil create -volname "$NAME" -srcfolder "$TEMP/root" -ov -format UDZO "$TEMP/output.dmg"
codesign --force --sign "$IDENTITY" --timestamp "$TEMP/output.dmg"
xcrun notarytool submit "$TEMP/output.dmg" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$TEMP/output.dmg"
xcrun stapler validate "$TEMP/output.dmg"
spctl --assess --type open --context context:primary-signature "$TEMP/output.dmg"
mv -f "$TEMP/output.dmg" "$OUTPUT"
(cd "$(dirname "$OUTPUT")" && shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")
echo "RELEASE_ARTIFACT_READY: $OUTPUT"
