# Receptor — one repo, two pipelines (see AGENTS.md).
# macOS: releasing = git tag vX.Y.Z && git push origin vX.Y.Z (release-macos.yml
#   signs/notarizes and bumps the Homebrew cask) — no local macOS deploy verb.
# iOS: local build + cable install via the verbs below; no CI deploy.
# The .xcodeproj IS committed (no XcodeGen here) — edit the project in Xcode.

set shell := ["bash", "-cu"]

app := "Receptor"
# Alex's iPhone; override with IOS_DEVICE_ID for another device
device_id := env_var_or_default("IOS_DEVICE_ID", "00008140-000839E42111801C")
team_id := "467A4PRB8F"
# iOS build carries NO entitlements (app group is macOS-only), so STABLE
# signing uses the team-wide wildcard Ad Hoc profile.
profile := env_var_or_default("IOS_PROFILE", "Alexander Wildcard Ad Hoc")

default:
    @just --list

# open in Xcode for the normal edit/run loop
dev:
    open {{app}}.xcodeproj

# unsigned builds for both platforms — the CI-able correctness gate
# (no `test` verb: the project has no test target yet)
check:
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "generic/platform=iOS Simulator" \
      CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=macOS" \
      CODE_SIGNING_ALLOWED=NO build

# iOS DEBUG build + install: automatic signing, 7-day validity, readable logs.
# CURRENTLY BROKEN: no Apple Development cert exists (the expired one was
# deleted 2026-08-01). Regenerating one (+ signing into Xcode) restores this
# mode — optional, STABLE covers daily use. See AGENTS.md "Signing".
build:
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=iOS,id={{device_id}}" \
      -configuration Debug -allowProvisioningUpdates build
    APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/{{app}}-*/Build/Products/Debug-iphoneos/{{app}}.app | head -1) && \
      xcrun devicectl device install app --device {{device_id}} "$APP"

# iOS STABLE build + install: Ad Hoc distribution, 1-year validity, no logs.
# Run `just signing-setup` first if the keychain cache is empty.
deploy:
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=iOS,id={{device_id}}" \
      -configuration Release \
      CODE_SIGN_STYLE="Manual" \
      CODE_SIGN_IDENTITY="Apple Distribution" \
      PROVISIONING_PROFILE_SPECIFIER="{{profile}}" \
      DEVELOPMENT_TEAM={{team_id}} \
      clean build
    APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/{{app}}-*/Build/Products/Release-iphoneos/{{app}}.app | head -1) && \
      xcrun devicectl device install app --device {{device_id}} "$APP"

# Pull signing material from the 1P `Apple Signing` vault into the login
# keychain + profile dirs. 1P is the only durable home for certs — the local
# keychain is a disposable cache; run signing-cleanup when done building.
# MUST run from Alex's own terminal (desktop-authed op): the claude-code
# service account cannot see the Apple Signing vault.
signing-setup:
    #!/usr/bin/env bash
    # IDs, not names (Apple Signing vault / Apple Distribution Cert + Wildcard Ad Hoc Profile)
    # - rename-proof; see the IDs-over-names rule in global AGENTS.md.
    set -euo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    op read "op://xxbixvqoaicfykrbte6oh57ahq/fjlhndynlojmvcvhcei6qblsxm/p12_base64" | base64 -d > "$tmp/dist.p12"
    security import "$tmp/dist.p12" -k ~/Library/Keychains/login.keychain-db \
      -P "$(op read "op://xxbixvqoaicfykrbte6oh57ahq/fjlhndynlojmvcvhcei6qblsxm/password")" \
      -T /usr/bin/codesign -T /usr/bin/security
    rm "$tmp/dist.p12"
    op read "op://xxbixvqoaicfykrbte6oh57ahq/npastowgp6rn5mybxeek5mqseu/mobileprovision_base64" | base64 -d > "$tmp/profile.mobileprovision"
    uuid=$(security cms -D -i "$tmp/profile.mobileprovision" | plutil -extract UUID raw -o - -)
    mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
             "$HOME/Library/MobileDevice/Provisioning Profiles"
    cp "$tmp/profile.mobileprovision" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$uuid.mobileprovision"
    cp "$tmp/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"
    echo "imported Apple Distribution identity + wildcard profile ($uuid)"

# Remove what signing-setup installed — keychain stays empty between build
# sessions; 1P remains the single durable copy.
signing-cleanup:
    #!/usr/bin/env bash
    set -euo pipefail
    hash=$(security find-identity -v -p codesigning | awk '/Apple Distribution/ {print $2; exit}') || true
    if [ -n "${hash:-}" ]; then
      security delete-identity -Z "$hash" ~/Library/Keychains/login.keychain-db
      echo "deleted Apple Distribution identity $hash"
    else
      echo "no Apple Distribution identity in the keychain"
    fi
    for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
               "$HOME/Library/MobileDevice/Provisioning Profiles"; do
      for f in "$dir"/*.mobileprovision; do
        [ -e "$f" ] || continue
        name=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - - || true)
        if [ "$name" = "{{profile}}" ]; then rm "$f"; echo "removed $f"; fi
      done
    done

# collect last 5m of device logs into ./logs/ (requires sudo; app must be a DEBUG install)
logs:
    mkdir -p logs
    sudo log collect --device-udid {{device_id}} --last 5m --output ./logs/receptor.logarchive
    log show ./logs/receptor.logarchive \
      --predicate 'process == "{{app}}" OR process == "BackgroundShortcutRunner" OR (eventMessage CONTAINS "com.alexmiller.receptor" AND process IN {"runningboardd","nsurlsessiond","SpringBoard"})' \
      --style compact > ./logs/receptor-logs.txt
    @echo "wrote logs/receptor-logs.txt"

# --- project-specific ---

# Local macOS testing WITHOUT installing to /Applications — real installs
# come from the Homebrew cask after a tagged release. Debug build, ad-hoc
# signed in place, launched straight from build/.
mac-dev-run:
    xcodebuild -project {{app}}.xcodeproj -scheme {{app}} \
      -destination "platform=macOS" \
      -configuration Debug \
      -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=NO build
    codesign --force --deep --sign - "build/DerivedData/Build/Products/Debug/{{app}}.app"
    open "build/DerivedData/Build/Products/Debug/{{app}}.app"
