# Nix Release Package Implementation Plan

**Goal:** Install the verified macOS release declaratively without modifying its signed bundle or user state.

**Architecture:** A fixed-output ZIP feeds a no-fixup derivation. An opt-in nix-darwin module adds the package to the standard application set. Consumers pin the flake; Homebrew remains an alternative distributor.

**Approved constraints:** Version 2.0.3 and its published archive hash stay unchanged. Support both Darwin architectures. No signing, source rebuild, custom updater, credentials or user-state migration. An explicitly enabled Darwin activation transition removes only the verified old app-only cask without zap/force before Homebrew cleanup; it is disabled by default. Host integration remains with its owner.

- [x] Add a failing package verification command comparing the packaged app against the original archive and validating version, signature and stapled ticket.
- [x] Add flake, locked nixpkgs, release derivation and opt-in module; verify enabled/disabled/overridden package evaluation.
- [x] Build and verify unchanged bytes/signature; mutate a test copy to prove corruption is rejected.
- [x] Document installation/release pins and test the opted-in activation transition: absent/present/running/failure/unexpected-receipt paths, normal brew user, pre-cleanup ordering.
- [ ] Review, commit, push, verify CI and hand the exact output/module/commit to the host owner before activation.

Review focus: architecture compatibility; signed resource preservation; accidental dual installation; native enrollment/data retention; stale release pins.

Verification: both Darwin package builds/module checks pass; package bytes, signature and stapled ticket match the release. Corrupting a test copy is rejected. Nine migration tests pass; removing the running-app guard is detected. Actual laptop module evaluation preserves upgrade=false/cleanup=zap and runs migration as the brew user before bundle cleanup. Native build commands were replaced with declared unzip after portability review; forced sandbox mode is not verified because the daemon rejects that client setting. Final review has no remaining important findings. Host activation belongs to its integration owner.
