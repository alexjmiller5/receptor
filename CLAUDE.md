# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Receptor is a multi-platform SwiftUI app (iOS/macOS) that captures thoughts and syncs them to the Synapse backend. It uses an offline-first architecture where thoughts are persisted locally in SwiftData and synced reliably via a background wake mechanism.

See the parent `../CLAUDE.md` for comprehensive documentation including architecture, sync model, and detailed build/deploy commands.

## Quick Reference

### Build & Deploy (macOS)

```bash
# Build
xcodebuild -project Receptor.xcodeproj -scheme Receptor \
  -destination "platform=macOS" -allowProvisioningUpdates build

# Deploy (quit, remove old, copy new, codesign, launch)
# NOTE: pick the NEWEST DerivedData dir explicitly — a bare Receptor-* glob can
# match stale build dirs and cp will deploy the wrong (old) build.
osascript -e 'quit app "Receptor"' 2>/dev/null; \
  rm -rf /Applications/Receptor.app; \
  APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Receptor-*/Build/Products/Debug/Receptor.app | head -1); \
  cp -R "$APP" /Applications/; \
  codesign --force --deep --sign - /Applications/Receptor.app; \
  open /Applications/Receptor.app
```

### Build & Deploy (iOS)

**IMPORTANT: Always ask which mode before building for iOS.**

iOS builds use manually configured provisioning profiles. Team ID: `467A4PRB8F`. There are two modes:

> **Signing status as of 2026-07-16:** Alex removed the old Apple Development
> certificate and the Receptor/Synapse per-app provisioning profiles. The
> team-wide default is now the wildcard profile `"Alexander Wildcard Ad Hoc"`
> (`com.alexmiller.*`, see the `ios-app` template) — **but Receptor cannot
> use it**: the App Groups entitlement (`group.com.alexmiller.receptor`)
> requires its explicit App ID. Before the next iOS build works, recreate on
> developer.apple.com against the current Apple Distribution cert:
> - Mode B: a new "Receptor Ad Hoc Provisioning Profile" (explicit App ID
>   `com.alexmiller.receptor` with App Groups enabled + device).
> - Mode A additionally needs a new Apple Development certificate and a new
>   "Receptor Development Provisioning Profile".
> The commands below are unchanged once those exist.

#### Mode A: "DEBUG" (coding sessions, logs, 7-day validity)

Use this when debugging, viewing logs, or during active development.

```bash
# Build
xcodebuild -project Receptor.xcodeproj \
  -scheme Receptor \
  -destination "platform=iOS,id=00008140-000839E42111801C" \
  -configuration Debug \
  CODE_SIGN_STYLE="Manual" \
  CODE_SIGN_IDENTITY="Apple Development" \
  PROVISIONING_PROFILE_SPECIFIER="Receptor Development Provisioning Profile" \
  DEVELOPMENT_TEAM=467A4PRB8F \
  clean build

# Install
APP_PATH=$(ls -d ~/Library/Developer/Xcode/DerivedData/Receptor-*/Build/Products/Debug-iphoneos/Receptor.app | head -1) && \
  xcrun devicectl device install app --device 00008140-000839E42111801C "$APP_PATH"
```

#### Mode B: "STABLE" (travel/weekly use, no logs, 1-year validity)

Use this for long-term installs that work without a computer. Ad Hoc distribution.

```bash
# Build
xcodebuild -project Receptor.xcodeproj \
  -scheme Receptor \
  -destination "platform=iOS,id=00008140-000839E42111801C" \
  -configuration Release \
  CODE_SIGN_STYLE="Manual" \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="Receptor Ad Hoc Provisioning Profile" \
  DEVELOPMENT_TEAM=467A4PRB8F \
  clean build

# Install
APP_PATH=$(ls -d ~/Library/Developer/Xcode/DerivedData/Receptor-*/Build/Products/Release-iphoneos/Receptor.app | head -1) && \
  xcrun devicectl device install app --device 00008140-000839E42111801C "$APP_PATH"
```

#### iOS Build Rules

- **If user asks for logs** → Must use Mode A. Mode B strips `get-task-allow`, making logs unreadable.
- **If `xcodebuild` fails with "Profile doesn't match"** → Remind user to verify `.mobileprovision` files are installed in `~/Library/MobileDevice/Provisioning Profiles/`.
- **Never use `-allowProvisioningUpdates` or automatic signing** for iOS builds. Always use the manual profiles above.

### Collect & View iOS Device Logs

Logs are collected from the device and exported to `./logs/` in the repo root. Run from the `synapse/` directory.

```bash
# 1. Collect last 5 minutes from device (requires sudo)
sudo log collect --device-udid 00008140-000839E42111801C --last 5m --output ./logs/receptor.logarchive

# 2. Export filtered logs to readable text file
log show ./logs/receptor.logarchive \
  --predicate 'process == "Receptor" OR process == "BackgroundShortcutRunner" OR (eventMessage CONTAINS "com.alexmiller.receptor" AND process IN {"runningboardd","nsurlsessiond","SpringBoard"})' \
  --style compact > ./logs/receptor-logs.txt
```

Then read `./logs/receptor-logs.txt` for analysis. The predicate captures our custom os_log messages, Shortcuts runner events, and relevant system lifecycle logs while filtering out noise.

### Find Connected Devices

```bash
xcrun xctrace list devices 2>&1 | grep -i iphone
```

## Key Concepts

- **Thought** - The core data model (`Models/Thought.swift`), persisted in SwiftData
- **Recept** - The verb for capturing and sending a thought (e.g., `receptThought()`)
- **SyncManager** - Singleton that handles all sync operations, network monitoring, and background wake
- **App Group** - `group.com.alexmiller.receptor` enables data sharing with Shortcuts extensions

## Sync Flow

1. User input → `queueThought()` saves to SwiftData immediately
2. `requestFlush()` fires a background URLSession ping to `captive.apple.com`
3. When OS wakes the app, `handleBackgroundWakeCompleted()` triggers actual FIFO flush
4. Each thought: lock → `receptThought()` HTTP POST → unlock
5. On failure: stop flush, retry on next trigger

## Platform Differences

| Feature | iOS | macOS |
|---------|-----|-------|
| Background sync | BGTaskScheduler | Not needed (app stays running) |
| Menu bar | N/A | Brain icon with quick capture |
| Login item | N/A | SMAppService toggle in Settings |
| App lifecycle | AppDelegate handles events | Window/MenuBarExtra scenes |

## Code Organization

```
Receptor/
├── Models/Thought.swift       # SwiftData model + ThoughtStatus/SyncTrigger enums
├── Services/
│   ├── SyncManager.swift      # Core sync logic, network monitoring, background wake
│   ├── Configuration.swift    # App Group container, API key/URL storage
│   └── AppDelegate.swift      # iOS-only: background task registration
├── Intents/
│   ├── CaptureThoughtIntent.swift  # "Recept" - fire-and-forget
│   └── ReceptQueueIntent.swift     # "Recept Thought Queue" - flush trigger
├── Views/                     # ThoughtsTab, SettingsTab, ThoughtListView, etc.
└── macOS/                     # MenuBarView, LoginItemManager
```

## Critical Rules

1. **Always deploy after changes** - Build and install to both iOS device and macOS
2. **FIFO ordering** - Flush stops on first failure to preserve order
3. **Thoughts persist first** - Always saved to SwiftData before any network call
4. **Per-item locking** - 5-second lock prevents double-sends during concurrent flushes
