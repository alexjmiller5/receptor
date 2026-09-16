# Receptor — one repo, two pipelines (see AGENTS.md).
# macOS: releasing = git tag vX.Y.Z && git push origin vX.Y.Z (release-macos.yml
#   signs/notarizes and bumps the Homebrew cask) — no local macOS deploy verb.
# iOS: local build + install via the verbs below; no CI deploy.
# The .xcodeproj is GENERATED from project.yml (`just gen`) and committed.

set shell := ["bash", "-cu"]

app := "Receptor"
# Alex's iPhone; override with IOS_DEVICE_ID for another device
device_id := env_var_or_default("IOS_DEVICE_ID", "00008140-000839E42111801C")
team_id := "467A4PRB8F"
# Ad Hoc profile NAMES are per target in project.yml (Release config); this is
# the 1Password item holding all three .mobileprovision files (Apple Signing vault).
profiles_item := env_var_or_default("IOS_PROFILES_ITEM", "op://xxbixvqoaicfykrbte6oh57ahq/7qslvdkwugfvktwni4dmoigclq")

default:
    @just --list

# Regenerate the xcodeproj from project.yml.
gen:
    xcodegen generate --spec project.yml

# open in Xcode for the normal edit/run loop
dev: gen
    open {{app}}.xcodeproj

# unsigned builds for both platforms — the CI-able correctness gate
# (no `test` verb: the project has no test target yet)
check: gen
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "generic/platform=iOS Simulator" \
      CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=macOS" \
      CODE_SIGNING_ALLOWED=NO build

# iOS DEBUG build + install: automatic signing (Apple Development cert in the
# login keychain, Xcode signed in to the team), 7-day validity, readable logs.
# The first run also registers the App IDs / App Group in the portal.
build: gen
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=iOS,id={{device_id}}" \
      -configuration Debug \
      DEVELOPMENT_TEAM={{team_id}} -allowProvisioningUpdates build
    APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/{{app}}-*/Build/Products/Debug-iphoneos/{{app}}.app | head -1) && \
      xcrun devicectl device install app --device {{device_id}} "$APP"

# iOS STABLE build + install: Ad Hoc distribution, 1-year validity, no logs.
# Run `just signing-setup` first if the keychain cache is empty.
deploy: gen
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=iOS,id={{device_id}}" \
      -configuration Release \
      CODE_SIGN_STYLE="Manual" \
      CODE_SIGN_IDENTITY="Apple Distribution" \
      DEVELOPMENT_TEAM={{team_id}} \
      clean build
    APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/{{app}}-*/Build/Products/Release-iphoneos/{{app}}.app | head -1) && \
      xcrun devicectl device install app --device {{device_id}} "$APP"

# Pull signing material from the 1P `Apple Signing` vault into the login
# keychain + profile dirs. 1P is the only durable home for certs — the local
# keychain is a disposable cache; run signing-cleanup when done building.
# Runs against desktop-authed op (the vault is not visible to agent SAs).
signing-setup:
    #!/usr/bin/env bash
    # IDs, not names (Apple Signing vault / Apple Distribution Cert + the profiles item)
    # - rename-proof; see the IDs-over-names rule in global AGENTS.md.
    set -euo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    op read "op://xxbixvqoaicfykrbte6oh57ahq/fjlhndynlojmvcvhcei6qblsxm/p12_base64" | base64 -d > "$tmp/dist.p12"
    security import "$tmp/dist.p12" -k ~/Library/Keychains/login.keychain-db \
      -P "$(op read "op://xxbixvqoaicfykrbte6oh57ahq/fjlhndynlojmvcvhcei6qblsxm/password")" \
      -T /usr/bin/codesign -T /usr/bin/security
    rm "$tmp/dist.p12"
    mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
             "$HOME/Library/MobileDevice/Provisioning Profiles"
    for field in app_mobileprovision_base64 share_mobileprovision_base64 widgets_mobileprovision_base64; do
      op read "{{profiles_item}}/$field" | base64 -d > "$tmp/profile.mobileprovision"
      uuid=$(security cms -D -i "$tmp/profile.mobileprovision" | plutil -extract UUID raw -o - -)
      cp "$tmp/profile.mobileprovision" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$uuid.mobileprovision"
      cp "$tmp/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"
    done
    echo "✅ Distribution cert + 3 Ad Hoc profiles installed"

# Evict the keychain/profile cache again (1P keeps the durable copies).
signing-cleanup:
    #!/usr/bin/env bash
    set -euo pipefail
    security delete-identity -c "Apple Distribution" ~/Library/Keychains/login.keychain-db || true
    for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
      for f in "$dir"/*.mobileprovision; do
        [ -e "$f" ] || continue
        if security cms -D -i "$f" | grep -q "Receptor.*Ad Hoc"; then rm "$f"; fi
      done
    done
    echo "🧹 Signing cache cleared"

# Collect + filter 5m of device logs into logs/ (DEBUG install only)
logs:
    mkdir -p logs
    sudo log collect --device-udid {{device_id}} --last 5m --output logs/{{app}}.logarchive
    log show logs/{{app}}.logarchive --predicate 'subsystem == "com.alexmiller.receptor"' --style compact > logs/{{app}}-logs.txt
    @echo "wrote logs/{{app}}-logs.txt"

# Local macOS testing from build/, no /Applications install
mac-dev-run: gen
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=macOS" -configuration Debug \
      -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
    open build/DerivedData/Build/Products/Debug/{{app}}.app
