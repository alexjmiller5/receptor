#!/usr/bin/env bash
# CI-only, ephemeral signing material. Only an encrypted IPA leaves the runner.
set -euo pipefail
umask 077
scratch=$(mktemp -d)
keychain="$scratch/signing.keychain-db"
security list-keychains -d user > "$scratch/keychains"
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  python3 - "$scratch/keychains" <<'PY'
import shlex, subprocess, sys
subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *shlex.split(open(sys.argv[1]).read())], check=True)
PY
  for p in "$scratch"/*.mobileprovision; do
    [ -f "$p" ] || continue
    uuid=$(basename "$p")
    rm -f "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$uuid"
  done
  python3 - "$scratch" build/Payload build/Receptor.ipa <<'PY'
import pathlib, shutil, sys
for name in sys.argv[1:]:
    p = pathlib.Path(name)
    if p.is_dir(): shutil.rmtree(p)
    else: p.unlink(missing_ok=True)
PY
}
trap cleanup EXIT
password=$(uuidgen)
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
printf '%s' "$IOS_CERTIFICATE_P12_BASE64" | base64 -d > "$scratch/cert.p12"
security import "$scratch/cert.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
for profile in IOS_APP_PROFILE IOS_SHARE_PROFILE IOS_SEND_PROFILE IOS_PREFILLED_PROFILE; do
  printf '%s' "${!profile}" | base64 -d > "$scratch/profile"
  security cms -D -i "$scratch/profile" > "$scratch/profile.plist"
  uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$scratch/profile.plist")
  team=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$scratch/profile.plist")
  cp "$scratch/profile" "$scratch/$uuid.mobileprovision"
  for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    mkdir -p "$dir"
    cp "$scratch/profile" "$dir/$uuid.mobileprovision"
  done
done
xcodebuild -project Receptor.xcodeproj -scheme Receptor -destination 'generic/platform=iOS' \
  -configuration Release -derivedDataPath "$scratch/DerivedData" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' DEVELOPMENT_TEAM="$team" build > "$scratch/build.log" 2>&1 \
  || { tail -100 "$scratch/build.log"; exit 1; }
mkdir -p build/Payload
ditto "$scratch/DerivedData/Build/Products/Release-iphoneos/Receptor.app" build/Payload/Receptor.app
codesign --verify --deep --strict build/Payload/Receptor.app
(cd build && zip -qry Receptor.ipa Payload)
age -r "$ARTIFACT_RECIPIENT" -o build/Receptor.ipa.age build/Receptor.ipa
