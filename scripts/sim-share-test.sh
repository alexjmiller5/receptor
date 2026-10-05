#!/usr/bin/env bash
# Run one share-sheet action on a simulator against a local fake backend and
# leave screenshots behind: the UI test's own steps plus a continuous frame
# capture from the host (the only way to catch a banner or a transient sheet).
#
# usage: scripts/sim-share-test.sh "<action label>" [out-dir]
# Env: IOS_SIM_UDID (default: the first available iPhone), IOS_DERIVED_DATA.
set -euo pipefail

action="${1:?usage: sim-share-test.sh \"<action label>\" [out-dir]}"
out="${2:-$(mktemp -d)}"
udid="${IOS_SIM_UDID:-$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(d["udid"] for r in json.load(sys.stdin)["devices"].values() for d in r if d["name"].startswith("iPhone")))')}"
dd="${IOS_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Receptor-sim}"
port=8799
mkdir -p "$out/steps" "$out/frames"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

"$(realpath "$(command -v xcodegen)")" generate --spec project.yml >/dev/null
xcodebuild -project Receptor.xcodeproj -scheme Receptor \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$dd" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  build-for-testing > "$out/build.log" 2>&1 || { grep -E "error:" "$out/build.log" | sort -u | head; exit 1; }

# Fake backend: accepts every POST, records the body.
cat > "$out/intaker.py" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        open(sys.argv[2], "ab").write(body + b"\n")
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(b'{"status":"accepted"}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
: > "$out/received.jsonl"
python3 "$out/intaker.py" "$port" "$out/received.jsonl" & intaker=$!
capture=""
trap 'kill $intaker 2>/dev/null || true; [ -n "$capture" ] && kill $capture 2>/dev/null || true' EXIT

xcrun simctl install "$udid" "$dd/Build/Products/Debug-iphonesimulator/Receptor.app"
xcrun simctl launch "$udid" com.alexmiller.receptor >/dev/null; sleep 3
xcrun simctl terminate "$udid" com.alexmiller.receptor >/dev/null 2>&1 || true
group=$(xcrun simctl get_app_container "$udid" com.alexmiller.receptor groups | awk '{print $2}' | head -1)
prefs="$group/Library/Preferences/group.com.alexmiller.receptor"
mkdir -p "$group/Library/Preferences"
xcrun simctl openurl "$udid" "https://example.com"; sleep 3
( i=0; while :; do i=$((i+1)); xcrun simctl io "$udid" screenshot --type=png "$out/frames/$(printf 'f%04d' $i).png" >/dev/null 2>&1 || true; done ) & capture=$!

set +e
TEST_RUNNER_SHOTS_DIR="$out/steps" TEST_RUNNER_SHARE_ACTION="$action" \
  xcodebuild -project Receptor.xcodeproj -scheme Receptor \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$dd" \
  -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:ReceptorUITests/ShareSheetUITests test-without-building > "$out/test.log" 2>&1
status=$?
set -e
kill $capture 2>/dev/null || true; capture=""

# Keep one frame per distinct screen.
( cd "$out/frames" && prev="" && for f in f*.png; do h=$(md5 -q "$f"); if [ "$h" = "$prev" ]; then rm "$f"; else prev="$h"; fi; done )
echo "test exit: $status"
python3 - "$out/received.jsonl" "$action" <<'PYTEST'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
source = {"Receptor 📥": "share-send", "Receptor 📤 💭": "share-context", "Pre-filled Receptor 📤": "share-prefilled"}[sys.argv[2]]
expected = "https://example.com/" + (" $ from the ui test" if source == "share-context" else "")
assert any(r.get("source") == source and r.get("raw_text") == expected for r in rows), rows
print("Verified capture payload and source")
PYTEST
echo "steps: $out/steps  frames: $out/frames ($(ls "$out/frames" | wc -l | tr -d ' ') distinct)"
grep -E "banner|SHARE" "$group/debug.log" 2>/dev/null | tail -3 || true
exit $status
