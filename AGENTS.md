# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Receptor is a multi-platform SwiftUI app (iOS/macOS) that captures thoughts and syncs them to the Synapse backend. It uses an offline-first architecture where thoughts are persisted locally in SwiftData and synced reliably via a background wake mechanism.

See the Synapse repo's `../synapse/AGENTS.md` for comprehensive documentation including architecture and the sync model.

## One repo, two pipelines

One Xcode target builds both platforms (`SDKROOT = auto`); the two platforms ship completely differently:

| | macOS | iOS |
|---|---|---|
| Ship | Push tag `vX.Y.Z` → `release-macos.yml` → Developer ID sign + notarize + staple → GH release → cask `receptor` bumped in [alexjmiller5/homebrew-tap](https://github.com/alexjmiller5/homebrew-tap) | Local build + cable install via justfile (no CI deploy) |
| Install | Declaratively via nix-config: `homebrew.taps = ["alexjmiller5/tap"]`, `homebrew.casks = ["receptor"]` | `just deploy` (STABLE) / `just build` (DEBUG) |
| Local dev | `just mac-dev-run` — Debug build launched from `build/`, never installed to /Applications | same verbs |

**The old macOS rm-cp-codesign deploy one-liner is dead.** /Applications/Receptor.app comes from the cask after a tagged release; never copy a build there by hand. After pushing a tag, verify with `gh run watch <id> --exit-status` — never assume the release succeeded.

The `.xcodeproj` IS committed (this repo predates the XcodeGen templates — no `project.yml`, no `just gen`). The shared scheme lives at `Receptor.xcodeproj/xcshareddata/xcschemes/Receptor.xcscheme` (CI depends on it); `xcuserdata/` is gitignored.

## Commands

| Command | Purpose |
|---|---|
| `just dev` | Open Xcode |
| `just check` | Unsigned iOS-simulator + macOS builds — the CI gate (`check.yml`) |
| `just build` | iOS DEBUG build + cable install (7-day signing, readable logs) — **currently broken**, see below |
| `just deploy` | iOS STABLE build + cable install (1-year Ad Hoc signing) |
| `just signing-setup` | Pull Apple Distribution cert + wildcard profile from 1Password into the keychain |
| `just signing-cleanup` | Remove them again (keychain is only a cache) |
| `just logs` | Collect + filter 5m of device logs into `logs/` (DEBUG install only) |
| `just mac-dev-run` | Local macOS testing from `build/`, no /Applications install |

No test verb yet — the project has no test target.

## Signing

**Signing material lives in 1Password (`Apple Signing` vault), not the keychain.** `just signing-setup` / `just signing-cleanup` cache and evict it; both must run from Alex's OWN terminal (desktop-authed `op`) — the claude-code service account cannot see that vault, so Claude pastes the command instead of running it. Team ID: `467A4PRB8F` (injected via CLI; the pbxproj carries no team).

- **macOS (CI)**: Developer ID Application cert + hardened runtime + notarization, in `release-macos.yml`. The macOS entitlements file (`Receptor/Receptor-macOS.entitlements`: app group `group.com.alexmiller.receptor`, sandbox off) is passed explicitly to `codesign` — app groups work with Developer ID without a provisioning profile, and the workflow fails if the entitlement doesn't survive the re-sign.
- **iOS**: two modes, manual profiles, never `-allowProvisioningUpdates` for STABLE:

| Mode | Recipe | Signing | Validity | Logs |
|---|---|---|---|---|
| A: DEBUG (dev loop) | `just build` | Automatic, Apple Development | 7 days | readable |
| B: STABLE (daily use) | `just deploy` | Manual, Apple Distribution + `"Alexander Wildcard Ad Hoc"` | 1 year | stripped |

> **Signing status (2026-08-01, still current):** iOS STABLE uses the team-wide
> wildcard profile `"Alexander Wildcard Ad Hoc"` (`com.alexmiller.*`, expires
> 2027-02-13) with the Apple Distribution cert. To make that possible the App
> Groups entitlement was dropped from the **iOS** build (wildcard App IDs can't
> carry it; `Receptor/Receptor.entitlements` is empty); iOS stores SwiftData +
> settings in the app's own container via `Configuration.sharedContainerURL`.
> macOS keeps the group container — its data lives there.
> On iPhone reinstall: settings (API key/secret/intaker URL) must be re-entered
> once, and data in the old group container is orphaned.
> **Mode A (DEBUG) is still broken**: no Apple Development cert exists (the
> expired one was deleted from the keychain 2026-08-01). Restoring it is an
> optional Alex task: new dev cert + Xcode signed into the Apple ID (automatic
> signing then handles the profile).

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
- **App Group** - `group.com.alexmiller.receptor`, **macOS only** (iOS dropped it for wildcard signing); all storage paths route through `Configuration.sharedContainerURL`

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

1. **Ship changes down the right pipeline** - iOS: cable install via `just deploy` (or `just build` once Mode A works). macOS: test locally with `just mac-dev-run`; users get it by tagging a release — never hand-copy into /Applications
2. **FIFO ordering** - Flush stops on first failure to preserve order
3. **Thoughts persist first** - Always saved to SwiftData before any network call
4. **Per-item locking** - 40-second lock (outlives the 30s HTTP timeout) prevents double-sends during concurrent flushes; a `.sending` thought with an expired lock is treated as stale (process died mid-send) and resent on the next flush
