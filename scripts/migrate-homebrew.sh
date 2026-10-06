#!/usr/bin/env bash
# Invoked only by the opt-in Darwin activation, as the configured Homebrew user.
set -euo pipefail
prefix="${1:?Homebrew prefix required}"
receipt="$prefix/Caskroom/receptor/.metadata/INSTALL_RECEIPT.json"
fail() { printf 'Receptor migration: %s\n' "$*" >&2; exit 1; }
[[ "$(id -u)" != 0 ]] || fail 'must run as the Homebrew user, not root'
if [[ ! -e "$receipt" ]]; then
  [[ ! -d "$prefix/Caskroom/receptor/.metadata" ]] || fail 'installed metadata has no receipt'
  exit 0
fi
jq -e '
  .source.tap == "alexjmiller5/tap" and
  .uninstall_flight_blocks == false and
  .uninstall_artifacts == [{"app": ["Receptor.app"]}]
' "$receipt" >/dev/null || fail 'receipt is not the expected app-only Receptor cask'
status=0
pgrep -x Receptor >/dev/null || status=$?
case "$status" in
  0) fail 'Receptor is running; preserve drafts and quit it before switching' ;;
  1) ;;
  *) fail 'could not inspect running applications' ;;
esac
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_AUTOREMOVE=1 \
  "$prefix/bin/brew" uninstall --cask alexjmiller5/tap/receptor
[[ ! -e "$receipt" ]] || fail 'uninstall left its receipt; refusing subsequent cleanup'
