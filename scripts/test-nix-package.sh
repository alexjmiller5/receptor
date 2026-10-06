#!/usr/bin/env bash
# Detect packaging changes that alter the published signed bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
package="${1:-$(nix build .#receptor --no-link --print-out-paths)}"
archive="$(nix build .#receptor.src --no-link --print-out-paths)"
scratch="$(mktemp -d)"
trap '/usr/bin/find "$scratch" -depth -delete' EXIT
/usr/bin/ditto -x -k "$archive" "$scratch"
app="$package/Applications/Receptor.app"
diff -qr "$scratch/Receptor.app" "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/xcrun stapler validate "$app"
expected="$(nix eval --raw .#receptor.version)"
actual="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$actual" == "$expected" ]]
printf 'PASS: release bytes, version, signature and stapled ticket preserved\n'
