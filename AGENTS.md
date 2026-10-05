# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Receptor is a multi-platform SwiftUI app (iOS/macOS) that captures thoughts and syncs them to the Synapse backend. It uses an offline-first architecture where thoughts are persisted locally in SwiftData and synced reliably via a background wake mechanism.

Every capture surface is native - there are no Shortcuts in the loop:

| Surface | Target | Mechanism |
|---|---|---|
| App Shortcut, Action Button, Siri, Spotlight | Receptor | the `Recept` App Shortcut (`CaptureThoughtIntent`): run without a thought, iOS asks in its own sheet ("Enter your thought 💭", multi-line) and the app never opens. The user adds it through the system Shortcuts widget / "Shortcut" control |
| Share sheet, actions list: "Receptor 📥" | ReceptorSend | action extension, no screen: sends the link/text as-is |
| Share sheet: "Receptor 📤 💭" | ReceptorShare | action extension with a sheet asking "Enter your context", sends `input $ context` |
| Share sheet: "Pre-filled Receptor 📤" | ReceptorPrefilled | action extension, no screen: appends the context configured for the link's host in Settings (`Configuration.domainContexts`), else the catch-all, else as-is |
| Mac hotkeys / agents | Receptor (macOS) | `receptor://recept?text=&source=` handled in `MacAppDelegate.application(_:open:)`, silent; `receptor://compose` shows `QuickCapturePanel` (floating non-activating prompt, Return saves, inline checkmark confirms) - callers use `open -g` so the app is never activated and the main window never opens for a capture |

The two one-tap actions use `NSExtensionRequestHandling` with no screen. They
complete quietly on success. The context action owns a sheet and briefly reports
the upload outcome inline. All three use `ExtensionInput.finish` for persistence,
upload, failure notifications and completion. Never add a success-only extension
view: iOS presents it as a full-height sheet covering the source page.

See the Synapse repo's `../synapse/AGENTS.md` for comprehensive documentation including architecture and the sync model.

## One repo, two pipelines

One Xcode target builds both platforms (`SDKROOT = auto`); the two platforms ship completely differently:

| | macOS | iOS |
|---|---|---|
| Ship | Push tag `vX.Y.Z` → `release-macos.yml` → Developer ID sign + notarize + staple → GH release → cask `receptor` bumped in [alexjmiller5/homebrew-tap](https://github.com/alexjmiller5/homebrew-tap) | Manual `release-ios.yml` dispatch, encrypted Ad Hoc artifact |
| Install | Declaratively via nix-config: `homebrew.taps = ["alexjmiller5/tap"]`, `homebrew.casks = ["receptor"]` | Decrypt and verify CI IPA, then device install / `just ota` |
| Local dev | `just mac-dev-run` - Debug build launched from `build/`, never installed to /Applications | same verbs |

/Applications/Receptor.app comes from the cask after a tagged release; never copy a build there by hand. After pushing a tag, verify with `gh run watch <id> --exit-status` - never assume the release succeeded.

**Versions:** a macOS release happens only when Alex asks for one, and only its release commit changes `MARKETING_VERSION`. iOS cable installs are not releases and never bump it. When to release and which number: the `semver` skill.

The `.xcodeproj` is GENERATED from `project.yml` by XcodeGen (`just gen`) and committed so CI needs no xcodegen. Edit `project.yml`, never the project in Xcode. Four product targets: `Receptor` (multiplatform app, `supportedDestinations: [iOS, macOS]`) and the iOS-only action extensions `ReceptorSend`, `ReceptorShare`, `ReceptorPrefilled` (embedded with `platformFilter: iOS` so the macOS build ignores them; one shared `Shared/Extension.entitlements`). `Shared/` is compiled into all three action extensions. XcodeGen leaves `SUPPORTED_PLATFORMS` empty on multi-destination targets and `SDKROOT` unset on the extensions - both are pinned explicitly in `project.yml`, keep them.

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
| `just test` | Unit tests (`ReceptorTests`) on a simulator (`IOS_SIMULATOR` picks the device, default iPhone 17) |
| `just check` | Unsigned iOS-simulator + macOS builds - the CI gate (`check.yml`) |
| `just sim-share "<action>"` | Run a share-sheet action on a simulator against a fake backend; leaves step screenshots and every distinct frame. **Look at them before any phone install that touches a share action** |
| `just build` | iOS DEBUG build + cable install (7-day signing, readable logs) |
| `just deploy` | iOS STABLE build into `build/Receptor.ipa` + install over the local network; phone unreachable = ask the owner: `just ota` or cable |
| `just ota` | Serve `build/Receptor.ipa` as an install page on this machine's tailnet name (one tap on the phone, any network; blocks while serving) |
| `just signing-setup` | Pull the Apple Distribution cert + the four Ad Hoc profiles from 1Password into the keychain / profile dirs |
| `just signing-cleanup` | Remove them again (keychain is only a cache) |
| `just logs` | Collect + filter 5m of device logs into `logs/` (DEBUG install only) |
| `just mac-dev-run` | Local macOS testing from `build/`, no /Applications install |

`just test` runs `ReceptorTests` (Swift Testing, pure `Shared/` logic) on an iOS simulator. The simulator build is ad-hoc signed (`CODE_SIGN_IDENTITY=-`): an unsigned build has no App Group entitlement and the app crashes at launch on the nil container.

> **Shortcuts-actions gotcha:** every launched build (DerivedData, `build/`)
> registers with LaunchServices under `com.alexmiller.receptor`. Deleting those
> build dirs leaves dangling registrations that can shadow /Applications and
> break macOS Shortcuts with "action could not be found" (bit us 2026-08-06).
> Fix: `lsregister -u <dead path>` for each ghost, `lsregister -f
> /Applications/Receptor.app`, relaunch the app. Check registrations with
> `lsregister -dump | grep -E "^path:.*Receptor"` (lsregister lives under
> `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/`).

## Signing and releases

macOS releases use `release-macos.yml`: push an approved version tag, then verify
signing, notarization, the GitHub release and the cask update.

iOS releases use manual `release-ios.yml` dispatch with an ephemeral age public
key as `artifact_recipient`. CI reads the shared Apple Signing credentials using
the project's own CI service account, signs the app and all three extensions in
a temporary keychain, and uploads only an encrypted IPA with one-day retention.
Download and decrypt locally, verify all bundle signatures and embedded profiles,
then install the existing artifact through the paired host or `just ota`.
Never upload an unencrypted IPA or signing material as a CI artifact. Delete the
temporary age identity after decryption. Local `just deploy` is a fallback only
with a stated reason; normal development uses simulator builds.

The app and `.share`, `.send`, `.prefilled` App IDs each carry
`group.com.alexmiller.receptor`. Each target has a separate Ad Hoc profile in
`project.yml`. Profiles live in the shared Apple Signing vault item referenced by
the justfile. When registering a target, assign its App Group in the developer
portal before minting a profile with `scripts/asc-adhoc-profiles.py`.

## Connection (no developer credentials in the app)

A device talks to its capture service (Synapse's `synapse-capture` endpoint) with its OWN token: `Authorization: Bearer <token>`. The token is minted by the service per device (`just clients issue "<device>"` in the synapse repo prints an enrollment link), never the operator's Modal proxy credentials.

- **Enrollment link**: the https page the service prints opens `receptor://enroll?url=<capture URL>&token=<token>`; `DeepLink.enroll` validates both (`Configuration.validIntakerURL` / `validToken`), `Configuration.enroll` stores them and `SyncManager.connectionChanged()` flushes everything queued while unconnected. Settings is read-only: "Connected to <host>" with Disconnect (`Configuration.disconnect`), or "Not connected" - the URL and token are never typed in, an enrollment link is the only way to connect.
- **Storage**: the URL in the App Group defaults, the token in the Keychain (`Shared/TokenStore.swift`); on iOS the item uses the App Group as its access group so the share extensions read it, on macOS the login keychain. Launch purges the Modal proxy credentials older builds kept in defaults (`Configuration.purgeLegacyCredentials`).
- **Refused credential**: 401/403 leaves the thought `.failed` (retried after re-enrollment) and posts one "access was refused" notification; any other 4xx is a payload rejection and is never retried (`ThoughtStatus.after(httpStatus:)`).
- **Friend-ready**: onboarding someone = `just clients issue "<their device>"` + send the link + an install (Mac: `brew install --cask alexjmiller5/tap/receptor`; iOS: an Ad Hoc build needs their UDID registered - TestFlight would remove that step). Revoking one device touches no other.

## Secrets

`.env.tpl` is the manifest: release secrets are name-based refs into the shared `Apple Signing` vault; the `Receptor` project vault holds only a placeholder (the app's only runtime secret is the per-device token from its enrollment link, kept in the Keychain). CI's single GH secret is `OP_SERVICE_ACCOUNT_TOKEN` (the `receptor-ci` SA, read on both vaults) - set up once via `op-project-bootstrap .env.tpl --repo alexjmiller5/receptor`.

## Key Concepts

- **Thought** - The core data model (`Models/Thought.swift`), persisted in SwiftData
- **Recept** - The verb for capturing and sending a thought (e.g., `receptThought()`)
- **SyncManager** - Singleton that handles all sync operations, network monitoring, and background wake
- **App Group** - `group.com.alexmiller.receptor` on both platforms; the SwiftData store, settings (`Configuration.sharedDefaults`), upload payload files and the debug log all live in the group container so the extensions see them (the capture token is in the Keychain, see Connection). iOS migrates a pre-App-Group install once (`Configuration.migrateLegacyContainerIfNeeded`).
- **Extension uploads** - a share-sheet extension uploads directly while it is alive (`ShareCapture.capture`, 10 s timeout) and writes the real outcome: `.sent`, `.rejected`, or left `.queued` for the app's flush. It holds a 20 s lock meanwhile, which the app's flush honors. Never hand an extension's upload to a background `URLSession`: a small upload finishes while the extension is still alive, the completion is delivered there, and the app never learns the row was sent

## Source stamp

Every thought carries an optional `source` (`Thought.source`), sent to Synapse
as the `source` payload field and logged on the execution's `Source` select.
Free-form, never parsed by the app; each surface stamps its own label:

| Surface | `source` |
|---|---|
| In-app compose button (`ComposeRouter.openCompose()`) | `ios-app` / `macos-app` (`Configuration.appSource`) |
| `receptor://compose?source=<label>` (iOS sheet / Mac `QuickCapturePanel`) | the link's `source`, else `ios-compose-link` / `macos-panel` |
| `receptor://recept?text=&source=<label>` | the link's `source` (Hammerspoon: `hammerspoon-hyper-r`, `hammerspoon-hyper-q`, `hammerspoon-chrome-url`; agents: `agent`) |
| Share sheet actions | `share-send` / `share-context` / `share-prefilled` |
| `Recept` App Shortcut | its optional Source parameter, else `app-shortcut` (iOS does not tell an intent whether the Lock Screen, Control Center, Action Button, Siri or Spotlight ran it) |

## Capture feedback

Successful captures and background syncs never post notifications. The Mac quick
panel confirms local persistence inline for 600 ms, then closes without activating
the app. The context share sheet briefly reports its actual upload outcome inline.
The no-UI share actions complete quietly. App Intent presentation belongs to iOS;
Receptor returns its value without a result dialog or success banner.

Only failures post notifications: rejected payloads, a missing/refused connection,
and persistence errors. Transient uploads remain queued for automatic retry.
Settings explains these failure alerts and warns when banners are unavailable.

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
Shared/                        # compiled into the app AND all three action extensions
├── Thought.swift              # SwiftData model + ThoughtStatus/SyncTrigger, uploadPayload
├── Configuration.swift        # App Group storage, settings, share-sheet default contexts
├── DeepLink.swift             # receptor://compose?source=, receptor://recept and receptor://enroll parsing
├── TokenStore.swift           # the device's capture token in the Keychain
├── ExtensionInput.swift       # reads the share-sheet input; finish() = capture + failure alert + completeRequest
├── ShareCapture.swift         # extension-side persistence + direct upload
├── Extension.entitlements     # App Group, shared by the three extensions
└── DebugFileLog.swift
Receptor/                      # the app (iOS + macOS)
├── Services/SyncManager.swift # Core sync logic, network monitoring, background wake
├── Services/AppDelegate.swift # iOS-only: background task registration, session events
├── Intents/                   # App Shortcuts (CaptureThoughtIntent, ReceptQueueIntent)
├── Views/                     # ContentView, ThoughtsTab, ComposeView, ComposeRouter, SettingsTab, ...
└── macOS/                     # MenuBarView (status item + deep links), LoginItemManager
ReceptorSend/                  # "Receptor 📥" action extension
ReceptorShare/                 # "Receptor 📤 💭" action extension (context alert)
ReceptorPrefilled/             # "Pre-filled Receptor 📤" action extension
ReceptorTests/                 # unit tests (just test)
ReceptorUITests/               # drives the real share sheet in Safari on a simulator
scripts/asc-adhoc-profiles.py  # register App IDs + mint the Ad Hoc profiles
scripts/sim-share-test.sh      # just sim-share: fake backend + UI test + frame capture
scripts/ota-install.sh         # just ota: tailnet install page
```

## Critical Rules

1. **Ship changes down the right pipeline** - iOS: manual CI signing, then install the verified artifact. macOS: test locally with `just mac-dev-run`; users get it by tagging a release - never hand-copy into /Applications
2. **FIFO ordering** - Flush stops on first failure to preserve order
3. **Thoughts persist first** - Always saved to SwiftData before any network call
4. **Every thought carries a `source`** naming the surface that captured it (table under Source stamp); a new capture surface gets its own label
5. **Per-item locking** - 40-second lock (outlives the 30s HTTP timeout) prevents double-sends during concurrent flushes; a `.sending` thought with an expired lock is treated as stale (process died mid-send) and resent on the next flush
