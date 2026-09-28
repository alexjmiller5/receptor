# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Receptor is a multi-platform SwiftUI app (iOS/macOS) that captures thoughts and syncs them to the Synapse backend. It uses an offline-first architecture where thoughts are persisted locally in SwiftData and synced reliably via a background wake mechanism.

Every capture surface is native - there are no Shortcuts in the loop:

| Surface | Target | Mechanism |
|---|---|---|
| Lock Screen widget | ReceptorWidgets | accessory widget, `widgetURL(receptor://compose)` |
| Control Center button | ReceptorWidgets | `ControlWidgetButton(OpenComposeIntent)` - `openAppWhenRun` + the `pendingCompose` flag in group defaults |
| Share sheet | ReceptorShare | `ShareViewController` → `ShareCapture.enqueue` (shared store + its own background upload session) |
| Mac hotkeys / agents | Receptor (macOS) | `receptor://recept?text=&source=` handled in `MacAppDelegate.application(_:open:)`; `receptor://compose` opens the window |
| Siri / Action Button | Receptor | App Shortcuts (`CaptureThoughtIntent`, `ReceptQueueIntent`) |

See the Synapse repo's `../synapse/AGENTS.md` for comprehensive documentation including architecture and the sync model.

## One repo, two pipelines

One Xcode target builds both platforms (`SDKROOT = auto`); the two platforms ship completely differently:

| | macOS | iOS |
|---|---|---|
| Ship | Push tag `vX.Y.Z` → `release-macos.yml` → Developer ID sign + notarize + staple → GH release → cask `receptor` bumped in [alexjmiller5/homebrew-tap](https://github.com/alexjmiller5/homebrew-tap) | Local build + cable install via justfile (no CI deploy) |
| Install | Declaratively via nix-config: `homebrew.taps = ["alexjmiller5/tap"]`, `homebrew.casks = ["receptor"]` | `just deploy` (STABLE) / `just build` (DEBUG) |
| Local dev | `just mac-dev-run` — Debug build launched from `build/`, never installed to /Applications | same verbs |

**The old macOS rm-cp-codesign deploy one-liner is dead.** /Applications/Receptor.app comes from the cask after a tagged release; never copy a build there by hand. After pushing a tag, verify with `gh run watch <id> --exit-status` — never assume the release succeeded.

The `.xcodeproj` is GENERATED from `project.yml` by XcodeGen (`just gen`) and committed so CI needs no xcodegen. Edit `project.yml`, never the project in Xcode. Three targets: `Receptor` (multiplatform app, `supportedDestinations: [iOS, macOS]`), `ReceptorShare` and `ReceptorWidgets` (iOS-only app extensions, embedded with `platformFilter: iOS` so the macOS build ignores them). `Shared/` is compiled into all three. XcodeGen leaves `SUPPORTED_PLATFORMS` empty on multi-destination targets and `SDKROOT` unset on the extensions - both are pinned explicitly in `project.yml`, keep them.

> **iCloud gotcha:** the repo lives under `~/Desktop` (iCloud). Never point
> `-derivedDataPath` inside the repo for a signed build - iCloud stamps
> extended attributes on the products and `codesign` fails with "resource
> fork, Finder information, or similar detritus". The default
> `~/Library/Developer/Xcode/DerivedData` is fine (the justfile uses it).

## Commands

| Command | Purpose |
|---|---|
| `just gen` | Regenerate `Receptor.xcodeproj` from `project.yml` (every other verb runs it first) |
| `just dev` | Open Xcode |
| `just check` | Unsigned iOS-simulator + macOS builds — the CI gate (`check.yml`) |
| `just build` | iOS DEBUG build + cable install (7-day signing, readable logs) |
| `just deploy` | iOS STABLE build + cable install (1-year Ad Hoc signing) |
| `just signing-setup` | Pull the Apple Distribution cert + the three Ad Hoc profiles from 1Password into the keychain / profile dirs |
| `just signing-cleanup` | Remove them again (keychain is only a cache) |
| `just logs` | Collect + filter 5m of device logs into `logs/` (DEBUG install only) |
| `just mac-dev-run` | Local macOS testing from `build/`, no /Applications install |

No test verb yet — the project has no test target.

> **Shortcuts-actions gotcha:** every launched build (DerivedData, `build/`)
> registers with LaunchServices under `com.alexmiller.receptor`. Deleting those
> build dirs leaves dangling registrations that can shadow /Applications and
> break macOS Shortcuts with "action could not be found" (bit us 2026-08-06).
> Fix: `lsregister -u <dead path>` for each ghost, `lsregister -f
> /Applications/Receptor.app`, relaunch the app. Check registrations with
> `lsregister -dump | grep -E "^path:.*Receptor"` (lsregister lives under
> `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/`).

## Signing

**Signing material lives in 1Password (`Apple Signing` vault), not the keychain.** `just signing-setup` / `just signing-cleanup` cache and evict it; both must run from Alex's OWN terminal (desktop-authed `op`) — the claude-code service account cannot see that vault, so Claude pastes the command instead of running it. Team ID: `467A4PRB8F` (injected via CLI; the pbxproj carries no team).

- **macOS (CI)**: Developer ID Application cert + hardened runtime + notarization, in `release-macos.yml`. The macOS entitlements file (`Receptor/Receptor-macOS.entitlements`: app group `group.com.alexmiller.receptor`, sandbox off) is passed explicitly to `codesign` — app groups work with Developer ID without a provisioning profile, and the workflow fails if the entitlement doesn't survive the re-sign.
- **iOS**: explicit App IDs (`com.alexmiller.receptor`, `.share`, `.widgets`), each with the App Groups capability configured to `group.com.alexmiller.receptor` in the developer portal (portal-only step: Xcode's automatic signing registers the App IDs and the capability but cannot assign the group; the App Store Connect API cannot either). Two modes, manual profiles, never `-allowProvisioningUpdates` for STABLE:

| Mode | Recipe | Signing | Validity | Logs |
|---|---|---|---|---|
| A: DEBUG (dev loop) | `just build` | Automatic, Apple Development | 7 days | readable |
| B: STABLE (daily use) | `just deploy` | Manual, Apple Distribution + one Ad Hoc profile per target (`Receptor Ad Hoc`, `Receptor Share Ad Hoc`, `Receptor Widgets Ad Hoc`, named in `project.yml`) | until the Distribution cert expires | stripped |

Ad Hoc profiles are minted by `scripts/asc-adhoc-profiles.py` (App Store Connect API; `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8` env, device UDIDs via `ASC_TEAM_DEVICE_UDIDS`) and stored as one item in the `Apple Signing` vault (`Receptor Ad Hoc Profiles`, three `*_mobileprovision_base64` fields; id in the justfile). Re-run the script + update the item when the cert rotates or a device is added.

> Mode A (DEBUG) needs an Apple Development cert in the login keychain and Xcode
> signed in to the team; dev certs are disposable (Xcode → Settings → Accounts
> → Manage Certificates → +) and deliberately not stored in 1Password.

iOS build rules:

- **If Alex asks for device logs** → must be a Mode A (DEBUG) install; Release strips `get-task-allow`.
- **"Profile doesn't match" / "no identity found"** → the keychain cache is empty; Alex runs `just signing-setup`.
- Device installs use `xcrun devicectl` (wired into the recipes). Alex's iPhone UDID is the justfile default; override with `IOS_DEVICE_ID`.
- Find connected devices: `xcrun xctrace list devices 2>&1 | grep -i iphone`

## Secrets

`.env.tpl` is the manifest: release secrets are name-based refs into the shared `Apple Signing` vault; the `Receptor` project vault holds only a placeholder (the app's runtime secrets are entered in Settings, not injected at build). CI's single GH secret is `OP_SERVICE_ACCOUNT_TOKEN` (the `receptor-ci` SA, read on both vaults) — set up once via `op-project-bootstrap .env.tpl --repo alexjmiller5/receptor`.

## Key Concepts

- **Thought** - The core data model (`Models/Thought.swift`), persisted in SwiftData
- **Recept** - The verb for capturing and sending a thought (e.g., `receptThought()`)
- **SyncManager** - Singleton that handles all sync operations, network monitoring, and background wake
- **App Group** - `group.com.alexmiller.receptor` on both platforms; the SwiftData store, settings (`Configuration.sharedDefaults`), upload payload files and the debug log all live in the group container so the share extension and widgets see them. iOS migrates a pre-App-Group install once (`Configuration.migrateLegacyContainerIfNeeded`).
- **Share extension upload** - the extension cannot wait for a response, so `ShareCapture` marks the thought `.sending` and hands the upload to a background `URLSession` with its own identifier; the app re-creates that session on launch (`SyncManager.backgroundSessionIdentifiers`) so the same delegate marks the thought sent/rejected

## Source stamp

Every thought carries an optional `source` (`Thought.source`), sent to Synapse
as the `source` payload field and logged there. The compose sheet stamps
`Configuration.appSource` (`ios-app` / `macos-app`); `CaptureThoughtIntent`
exposes it as the optional "Source" parameter, and each shortcut in
ios-shortcuts/notion passes its own label (`shortcut:<name>`, `hammerspoon`,
`agent`). Free-form, never parsed by the app.

## Failure surfacing

- `Configuration.validIntakerURL` gates the Settings URL field: only a full
  http(s) URL with a host is persisted, so a half-typed/cleared field never
  nils the stored URL (that silently rejected six captures on 2026-09-04).
- A `.rejected` (4xx) thought posts a local notification - it is never retried,
  so it is the one silent-loss path. `.failed` sends stay quiet (they retry).
- Not-configured posts one notification per process, and the intent returns
  "Queued locally — Receptor is not configured" instead of a bare "Queued".

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
project.yml                    # XcodeGen spec (targets, Info.plist keys, profile names)
Shared/                        # compiled into the app AND both extensions
├── Thought.swift              # SwiftData model + ThoughtStatus/SyncTrigger, uploadPayload
├── Configuration.swift        # App Group storage, settings, share-sheet default contexts
├── DeepLink.swift             # receptor://compose and receptor://recept parsing
├── ShareCapture.swift         # extension-side enqueue + background upload
├── OpenComposeIntent.swift    # Control Center button intent
└── DebugFileLog.swift
Receptor/                      # the app (iOS + macOS)
├── Services/SyncManager.swift # Core sync logic, network monitoring, background wake
├── Services/AppDelegate.swift # iOS-only: background task registration, session events
├── Intents/                   # App Shortcuts (CaptureThoughtIntent, ReceptQueueIntent)
├── Views/                     # ContentView, ThoughtsTab, ComposeView, ComposeRouter, SettingsTab, ...
└── macOS/                     # MenuBarView (status item + deep links), LoginItemManager
ReceptorShare/                 # share extension (ShareViewController + ShareView)
ReceptorWidgets/               # Lock Screen widget + Control Center control
scripts/asc-adhoc-profiles.py  # mint the three Ad Hoc profiles
```

## Critical Rules

1. **Ship changes down the right pipeline** - iOS: cable install via `just deploy` (or `just build` for the debug loop). macOS: test locally with `just mac-dev-run`; users get it by tagging a release — never hand-copy into /Applications
2. **FIFO ordering** - Flush stops on first failure to preserve order
6. **Every thought carries a `source`** (`Thought.source`, sent as the `source` payload field and logged by Synapse): `ios-app` / `macos-app` (compose sheet), `share-sheet`, `hammerspoon` / `agent` (deep links), plus whatever a Siri/App Shortcut caller passes. Free-form, never parsed by the app
3. **Thoughts persist first** - Always saved to SwiftData before any network call
4. **Per-item locking** - 40-second lock (outlives the 30s HTTP timeout) prevents double-sends during concurrent flushes; a `.sending` thought with an expired lock is treated as stale (process died mid-send) and resent on the next flush
