#!/usr/bin/env bash
# Serve a signed .ipa as an over-the-air install page on this machine's
# tailnet name: the phone opens the printed URL, taps Install, done. Works on
# any network the tailnet reaches (no shared Wi-Fi, no cable). Temporary by
# design: the page goes away after OTA_TTL seconds (default 900) or Ctrl-C,
# and nothing is left in the tailscale serve config.
#
# Env: OTA_TTL (seconds), OTA_HTTPS_PORT (default 443; 8443 and 10000 also work).
set -euo pipefail

ipa="${1:?usage: ota-install.sh <path/to/App.ipa>}"
[ -f "$ipa" ] || { echo "no such file: $ipa" >&2; exit 1; }
command -v tailscale >/dev/null || { echo "tailscale CLI not found" >&2; exit 1; }

host=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[ -n "$host" ] || { echo "this machine has no tailnet DNS name (is tailscale up, with HTTPS certificates enabled?)" >&2; exit 1; }
https_port="${OTA_HTTPS_PORT:-443}"
ttl="${OTA_TTL:-900}"
base="https://$host"; [ "$https_port" = "443" ] || base="$base:$https_port"

dir=$(mktemp -d)
http_pid=""; serve_pid=""
cleanup() {
  [ -n "$serve_pid" ] && kill "$serve_pid" 2>/dev/null || true
  [ -n "$http_pid" ] && kill "$http_pid" 2>/dev/null || true
  rm -rf "$dir"
}
trap cleanup EXIT INT TERM

cp "$ipa" "$dir/app.ipa"
info=$(unzip -Z1 "$ipa" | grep -E '^Payload/[^/]+\.app/Info\.plist$' | head -1)
[ -n "$info" ] || { echo "not an .ipa: no Payload/<App>.app/Info.plist inside $ipa" >&2; exit 1; }
unzip -p "$ipa" "$info" > "$dir/Info.plist"
bundle=$(plutil -extract CFBundleIdentifier raw -o - "$dir/Info.plist")
version=$(plutil -extract CFBundleShortVersionString raw -o - "$dir/Info.plist")
title=$(plutil -extract CFBundleDisplayName raw -o - "$dir/Info.plist" 2>/dev/null \
  || plutil -extract CFBundleName raw -o - "$dir/Info.plist")
title=$(printf '%s' "$title" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
rm "$dir/Info.plist"

cat > "$dir/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
  <key>assets</key><array><dict>
    <key>kind</key><string>software-package</string>
    <key>url</key><string>$base/app.ipa</string>
  </dict></array>
  <key>metadata</key><dict>
    <key>bundle-identifier</key><string>$bundle</string>
    <key>bundle-version</key><string>$version</string>
    <key>kind</key><string>software</string>
    <key>title</key><string>$title</string>
  </dict>
</dict></array></dict></plist>
PLIST
cat > "$dir/index.html" <<HTML
<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Install $title</title>
<body style="font:20px -apple-system;padding:48px 24px;text-align:center">
<h2>$title $version</h2>
<p><a style="display:inline-block;padding:16px 28px;border-radius:14px;background:#0a84ff;color:#fff;text-decoration:none" href="itms-services://?action=download-manifest&amp;url=$base/manifest.plist">Install</a></p>
</body>
HTML

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
(cd "$dir" && exec python3 -m http.server "$port" --bind 127.0.0.1) >/dev/null 2>&1 &
http_pid=$!
tailscale serve --https="$https_port" "http://127.0.0.1:$port" >/dev/null 2>&1 &
serve_pid=$!

ready=""
for _ in $(seq 1 30); do
  if [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$base/manifest.plist" || true)" = "200" ]; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || { echo "the install page never came up at $base/ (tailscale serve failed?)" >&2; exit 1; }

echo "install page: $base/"
echo "open it in Safari on the phone (tailnet connected) and tap Install - $title $version"
echo "serving for ${ttl}s; Ctrl-C stops it"
sleep "$ttl"
