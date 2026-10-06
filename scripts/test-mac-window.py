#!/usr/bin/env python3
"""Exercise the real Mac app with disposable storage and an isolated identity."""
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread

received = []


class CaptureService(BaseHTTPRequestHandler):
    def do_POST(self):
        assert self.headers["Authorization"] == "Bearer regression-token"
        received.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *args):
        pass


repo = Path(__file__).resolve().parents[1]
identity = "org.example.receptor.regression"
lsregister = (
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
    "LaunchServices.framework/Support/lsregister"
)
console = plistlib.loads(subprocess.check_output(["ioreg", "-a", "-n", "Root", "-d1"]))
if console.get("IOConsoleLocked"):
    raise SystemExit("Unlock this Mac before running its Accessibility regression test")

with tempfile.TemporaryDirectory(prefix="receptor-window-test-") as directory:
    work = Path(directory)
    source = work / "source"
    shutil.copytree(
        repo, source, symlinks=True,
        ignore=shutil.ignore_patterns(".git", "build", ".build", ".worktrees"),
    )
    # Keep UI/lifecycle production code intact; isolate only storage and identity.
    for path in source.rglob("*"):
        if (path.is_file() and not path.is_symlink()
                and path.suffix in {".swift", ".plist", ".pbxproj", ".yml", ".entitlements"}):
            path.write_text(
                path.read_text().replace("com.alexmiller.receptor", identity)
                .replace("<string>receptor</string>", "<string>receptor-regression</string>")
            )
    config = source / "Shared/Configuration.swift"
    substitutions = {
        'static let urlScheme = "receptor"': 'static let urlScheme = "receptor-regression"',
        "UserDefaults(suiteName: appGroupIdentifier)": f'UserDefaults(suiteName: "{identity}")',
        "FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)":
            'URL(fileURLWithPath: ProcessInfo.processInfo.environment["RECEPTOR_TEST_STORE"]!, isDirectory: true)',
        "get { TokenStore().load() }": 'get { "regression-token" }',
        "sharedDefaults?.string(forKey: intakerURLKey)":
            'ProcessInfo.processInfo.environment["RECEPTOR_TEST_URL"]',
    }
    text = config.read_text()
    for old, new in substitutions.items():
        assert text.count(old) == 1, f"Storage fixture no longer matches: {old}"
        text = text.replace(old, new)
    config.write_text(text)
    # Mirror the existing sync log to the disposable store for outcome assertions.
    sync = source / "Receptor/Services/SyncManager.swift"
    text = sync.read_text()
    anchor = "private func addLogEntry(_ message: String, trigger: SyncTrigger) {"
    assert text.count(anchor) == 1, "Sync log fixture no longer matches"
    sync.write_text(text.replace(anchor, anchor + "\n        DebugFileLog.write(message)"))
    store = work / "store"
    store.mkdir()
    app = work / "build/Build/Products/Debug/Receptor.app"
    server = HTTPServer(("127.0.0.1", 0), CaptureService)
    Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run(["xcodebuild", "-quiet", "-project", str(source / "Receptor.xcodeproj"),
                        "-scheme", "Receptor", "-destination", "platform=macOS",
                        "-derivedDataPath", str(work / "build"),
                        "CODE_SIGNING_ALLOWED=NO", "build"], check=True)
        subprocess.run(["osascript", str(repo / "scripts/test-mac-window.applescript"),
                        str(app), identity, str(store), f"http://127.0.0.1:{server.server_port}"], check=True)
        assert len(received) == 1, f"Expected one capture, received {received}"
        assert received[0]["raw_text"] == "Receptor regression capture"
        assert received[0]["source"] == "regression-test"
        log = (store / "debug.log").read_text()
        assert "FLUSH-COMPLETE sent=1" in log, "Capture did not finish syncing"
        assert "Notification:" not in log, "Successful capture posted a notification"
        print("PASS: capture reached the local service exactly once without a notification")
    except BaseException:
        print("Received:", received, flush=True)
        log = store / "debug.log"
        if log.exists():
            print(log.read_text()[-5000:], flush=True)
        raise
    finally:
        server.shutdown()
        server.server_close()
        # Only terminate a process launched from this test's temporary app.
        result = subprocess.run(["pgrep", "-f", str(app / "Contents/MacOS/Receptor")],
                                capture_output=True, text=True)
        for pid in result.stdout.split():
            pid = int(pid)
            try:
                os.kill(pid, 15)
                deadline = time.monotonic() + 5
                while True:
                    os.kill(pid, 0)
                    if time.monotonic() >= deadline:
                        os.kill(pid, 9)
                        break
                    time.sleep(0.05)
            except ProcessLookupError:
                pass
        subprocess.run([lsregister, "-u", str(app)], capture_output=True)
