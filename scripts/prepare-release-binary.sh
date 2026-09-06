#!/bin/bash
# Remove developer-machine debug paths before the enclosing app is signed.
set -euo pipefail
[[ $# -ge 1 ]] || { echo "Usage: prepare-release-binary.sh BINARY [...]" >&2; exit 64; }
for binary in "$@"; do
  [[ -f "$binary" ]] || { echo "Missing release executable." >&2; exit 66; }
  /usr/bin/strip -S -x "$binary"
  dependencies="$(/usr/bin/otool -L "$binary")"
  paths="$(/usr/bin/otool -l "$binary" | /usr/bin/awk '/cmd LC_RPATH/{found=1;next} found && /path / {sub(/^.*path /, "");sub(/ \(offset.*$/, "");print;found=0}' | /usr/bin/sort -u)"
  while IFS= read -r search_path; do
    case "$search_path" in
      /Users/*|/Library/Developer/*|*/Contents/Developer/Toolchains/*)
        # These apps link Swift and Apple frameworks from the OS. Do not remove
        # a runtime search path from a future app with unresolved dylib imports.
        if [[ "$dependencies" == *"@rpath/"* ]]; then
          echo "Bundle @rpath libraries before removing a developer runtime path." >&2
          exit 65
        fi
        /usr/bin/install_name_tool -delete_rpath "$search_path" "$binary"
        ;;
    esac
  done <<< "$paths"
  if /usr/bin/strings "$binary" | /usr/bin/grep -F "$HOME/" >/dev/null; then
    echo "Release executable still contains a developer home path." >&2
    exit 65
  fi
done
