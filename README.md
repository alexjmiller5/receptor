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

**macOS with Nix** - pin this flake in your nix-darwin configuration:

```nix
inputs.receptor.url = "github:alexjmiller5/receptor";
inputs.receptor.inputs.nixpkgs.follows = "nixpkgs";
# In the host's nix-darwin module list:
# inputs.receptor.darwinModules.default
# In the host configuration:
programs.receptor.enable = true;
```

The optional `programs.receptor.package` selects another release package.
`packages.aarch64-darwin.receptor` and `packages.x86_64-darwin.receptor`
(`default` aliases) unpack the published universal ZIP into
`$out/Applications/Receptor.app`. nix-darwin exposes it through its standard
`/Applications/Nix Apps` application set. The package never builds, patches,
strips or re-signs the app, and never manages enrollment or user data.
The default nixpkgs pin supports both architectures; Intel consumers must also
use a nixpkgs release that supports `x86_64-darwin`.

Build before switching your host. `nix flake check --all-systems` checks both
packages and module enable/disable/override behavior. Run
`bash scripts/test-nix-package.sh` on a Mac with Xcode command-line tools to
compare every packaged file with the archive and validate its version,
signature and stapled notarization ticket. It does not launch the app.

**Migrating an existing Homebrew install:**

1. Enable `programs.receptor.migrateFromHomebrew = true` for the migrating
   host, remove its Receptor cask declaration, and build the full host config.
   Keep the normal Homebrew upgrade and cleanup policy unchanged.
2. Finish or cancel any open capture yourself, then quit Receptor normally.
   Activate the already built host configuration through your normal workflow.
   The opt-in module runs before Homebrew's bundle/cleanup phase, as its
   configured user. It checks the exact Receptor receipt and refuses unexpected
   removal hooks, a running Receptor process, or an uninstall failure. It removes
   only that cask without `--zap` or `--force`, with Homebrew auto-update,
   install cleanup and unrelated formula auto-removal disabled. An absent receipt is a no-op;
   incomplete installed metadata fails closed.
3. Resolve the actual nix-darwin application alias (normally
   `/Applications/Nix Apps/Receptor.app`) and open that installed path. Do not
   reuse the removed `/Applications/Receptor.app` cask path or a working tree. Verify its
   version, existing thoughts and connection, then test compose/cancel and
   explicit window opening. The bundle and signing identities are unchanged;
   the transition leaves App Group/SwiftData files, preferences and Keychain
   items untouched. Disable `migrateFromHomebrew` after the transition; it is
   false by default and does not create a permanent updater.
4. If a saved launch path or login item still points to the old bundle, select
   the installed app through its supported UI. Manage Launch at Login in
   Receptor Settings. Do not edit login databases or recreate credentials.

Do not retain both installations. If activation fails after cask removal,
keep user data untouched and finish/retry the already verified Nix activation.
Run `python3 scripts/test-homebrew-migration.py` to exercise absent, present,
running, malformed-receipt and failure paths without touching an installed app.

A replacement machine enrolls through its own service-issued enrollment link;
Nix does not transfer another device's token or restore its native session.

**macOS without Nix** - the signed release is also available through
[Homebrew](https://github.com/alexjmiller5/homebrew-tap):
`brew install --cask alexjmiller5/tap/receptor`.

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

After publication, update `nix/package.nix` with the released version and the
published ZIP SHA-256, then run both Nix verification commands above and commit
the package pin. Consumers update their Receptor flake input and rebuild/switch
normally. The release tag itself predates that package-pin commit; pin the
packaging commit when selecting the new Nix release. Never substitute a locally
built app for the signed archive or disable fixup protection.
