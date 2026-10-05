# Receptor

Thought capture for iPhone and Mac. Offline-first SwiftUI app: thoughts are
saved locally (SwiftData) the instant you type them, then synced in FIFO
order to the [Synapse](https://github.com/alexjmiller5/synapse) backend via a
background-wake mechanism. On macOS it lives in the menu bar. On iOS the "Recept"
App Shortcut asks for a thought in the system sheet from the Lock Screen,
Control Center, the Action Button or Siri without opening the app, and the
share sheet offers three entries: send as-is, add a context, or append the
context you configured for that site. `receptor://compose` opens the compose sheet and
`receptor://recept?text=...&source=...` queues and sends a thought without UI
(hotkeys, agents). Every capture carries a `source` label that is forwarded to
the backend and logged with it.

## Install

**macOS** - Homebrew cask from
[alexjmiller5/homebrew-tap](https://github.com/alexjmiller5/homebrew-tap),
consumed declaratively via nix-config:

```nix
homebrew.taps = [ "alexjmiller5/tap" ];
homebrew.casks = [ "receptor" ];
```

(Or imperatively elsewhere: `brew install --cask alexjmiller5/tap/receptor`.)

**iOS** - Ad Hoc installation for registered devices. Run the manual
`release-ios` GitHub Actions workflow with a temporary age public key, download
and decrypt its encrypted IPA, then install through the Mac paired to the phone.
When local-network installation is unavailable, choose either a cable or a
Tailscale link (`just ota` serves `build/Receptor.ipa`). Signing happens in CI;
the installer does not need the signing certificate.

Successful captures stay quiet. The Mac prompt briefly confirms that the thought
was queued; the context share sheet confirms its upload outcome inline. Only
failed captures produce notifications.

## Lock Screen and Control Center

Use the system Shortcuts widget or Shortcut control and select Receptor's
bundled **Recept** App Shortcut. Leave its thought parameter empty so iOS asks
for the thought in its own prompt.

## Develop

```bash
just dev          # open Xcode
just check        # unsigned iOS-simulator + macOS builds (CI gate)
just mac-dev-run  # run a local macOS Debug build (no /Applications install)
just logs         # pull filtered device logs (DEBUG installs only)
```

## Releasing (macOS)

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

CI does the rest: builds, Developer-ID-signs (preserving the app-group
entitlement), notarizes, staples, publishes a GitHub release, and bumps
`Casks/receptor.rb` in the tap. See `AGENTS.md` for the full two-pipeline
picture and signing details.
