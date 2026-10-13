#!/usr/bin/env python3
"""Over-the-air install page for signed .ipa files, one list per machine.

`ota-install.py <App.ipa>` adds the app to this machine's install page at
https://<tailnet name>/install/ and prints that URL: the phone opens it in
Safari (Tailscale connected) and taps Install. Every project and agent on the
machine shares the page: a new app is appended, a newer build of an app
already listed replaces its entry, and each entry expires OTA_TTL_HOURS
(default 48) after it was added. The page server (stdlib http.server behind
`tailscale serve`) runs as a transient launchd job from a copy of this script
in the state dir; it prunes expired entries and, once the list is empty,
removes its `tailscale serve` path and its launchd job.

Env: OTA_TTL_HOURS, OTA_HTTPS_PORT (default 443), XDG_STATE_HOME.
"""

import fcntl
import html
import http.server
import json
import os
import plistlib
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile
from pathlib import Path

TTL = float(os.environ.get('OTA_TTL_HOURS', '48')) * 3600
PATH = '/install'
LABEL = 'ota-install.page'
STATE = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'ota-install'
if sys.argv[1:2] == ['serve']:  # the job runs the copy kept in the state dir
    STATE = Path(__file__).resolve().parent
BUTTON = ('display:inline-block;padding:16px 28px;border-radius:14px;'
          'background:#0a84ff;color:#fff;text-decoration:none')


def read_ipa(ipa):
    try:
        with zipfile.ZipFile(ipa) as z:
            name = next(n for n in z.namelist()
                        if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/') == 2)
            info = plistlib.loads(z.read(name))
    except (zipfile.BadZipFile, StopIteration):
        raise SystemExit(f'not an .ipa: no Payload/<App>.app/Info.plist inside {ipa}')
    return {'bundle': info['CFBundleIdentifier'],
            'version': info.get('CFBundleShortVersionString', ''),
            'build': info.get('CFBundleVersion', ''),
            'title': info.get('CFBundleDisplayName') or info.get('CFBundleName') or info['CFBundleIdentifier']}


def add(ipa, www, base, now):
    """Publish (or replace) the app's entry; the bundle id is the entry key."""
    entry = {**read_ipa(ipa), 'added': now, 'expires': now + TTL}
    # Plain URLs: iOS ignores an install link whose manifest URL has a query string.
    manifest = {'items': [{
        'assets': [{'kind': 'software-package', 'url': f"{base}/{entry['bundle']}/app.ipa"}],
        'metadata': {'bundle-identifier': entry['bundle'], 'bundle-version': entry['version'],
                     'kind': 'software', 'title': entry['title']}}]}
    www.mkdir(parents=True, exist_ok=True)
    staging = www / f".{entry['bundle']}.{os.getpid()}"
    staging.mkdir()
    shutil.copyfile(ipa, staging / 'app.ipa')
    (staging / 'manifest.plist').write_bytes(plistlib.dumps(manifest))
    (staging / 'entry.json').write_text(json.dumps(entry))
    final = www / entry['bundle']
    if final.exists():
        old = www / f".{entry['bundle']}.old.{os.getpid()}"
        final.rename(old)
        staging.rename(final)
        shutil.rmtree(old)
    else:
        staging.rename(final)
    return entry


def entries(www):
    found = []
    for meta in Path(www).glob('*/entry.json'):
        try:
            found.append(json.loads(meta.read_text()))
        except (OSError, ValueError):
            continue  # being replaced right now
    return sorted(found, key=lambda e: e['added'], reverse=True)


def prune(www, now):
    removed = []
    for e in entries(www):
        if now > e['expires']:
            shutil.rmtree(Path(www) / e['bundle'], ignore_errors=True)
            removed.append(e['bundle'])
    return removed


def render_index(listed, base):
    sections = ''.join(
        f"<section><h2>{html.escape(e['title'])} {html.escape(e['version'])}"
        f"{' (' + html.escape(e['build']) + ')' if e.get('build') else ''}</h2>"
        f"<p><a style=\"{BUTTON}\" href=\"itms-services://?action=download-manifest&amp;"
        f"url={base}/{e['bundle']}/manifest.plist\">Install</a></p></section>"
        for e in listed) or '<p>Nothing to install right now.</p>'
    return ('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>Install</title><body style="font:20px -apple-system;padding:48px 24px;text-align:center">'
            f'{sections}</body>')


def make_server(www, base, port):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kw):
            super().__init__(*args, directory=str(www), **kw)

        def send_body(self, body, kind):
            data = body.encode()
            self.send_response(200)
            self.send_header('Content-Type', kind)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            route = self.path.split('?')[0]
            if route == '/healthz':
                return self.send_body('ota-install', 'text/plain')
            if route in ('/', '/index.html'):
                prune(www, time.time())
                return self.send_body(render_index(entries(www), base), 'text/html; charset=utf-8')
            return super().do_GET()

        def list_directory(self, path):
            self.send_error(404)

        def log_request(self, code='-', size='-'):
            # One line per request (job log): shows whether a phone's installer fetched the manifest and app.
            agent = self.headers.get('User-Agent', '-') if self.headers else '-'
            sys.stderr.write(f'{time.strftime("%Y-%m-%dT%H:%M:%S")} {self.command} {self.path} {code} {size} {agent}\n')
            sys.stderr.flush()

        def log_message(self, *args):
            pass

    return http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)


def healthy(port):
    try:
        return urllib.request.urlopen(f'http://127.0.0.1:{port}/healthz', timeout=2).read() == b'ota-install'
    except OSError:
        return False


def serve(config):
    """The launchd job: serve until the list is empty, then take itself down."""
    www = STATE / 'www'
    server = make_server(www, config['base'], config['port'])
    threading.Thread(target=server.serve_forever, daemon=True).start()
    while True:
        time.sleep(600)
        with open(STATE / 'lock', 'w') as lock:  # an add waits, then restarts the page
            fcntl.flock(lock, fcntl.LOCK_EX)
            prune(www, time.time())
            if not entries(www):
                subprocess.run([config['tailscale'], 'serve', f"--https={config['https_port']}",
                                '--set-path', PATH, 'off'], capture_output=True)
                subprocess.run(['/bin/launchctl', 'remove', LABEL], capture_output=True)  # ends this process


def tailnet_base(tailscale, https_port):
    status = json.loads(subprocess.check_output([tailscale, 'status', '--json']))
    host = status['Self']['DNSName'].rstrip('.')
    if not host:
        raise SystemExit('this machine has no tailnet DNS name (is tailscale up, with HTTPS certificates enabled?)')
    return f'https://{host}' + ('' if https_port == '443' else f':{https_port}') + PATH


def ensure_page(tailscale, https_port, base):
    """Start the page server if it is not running and route /install to it."""
    config_file = STATE / 'config.json'
    config = json.loads(config_file.read_text()) if config_file.exists() else {}
    if not healthy(config.get('port', 0)):
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            port = s.getsockname()[1]
        config = {'port': port, 'base': base, 'tailscale': tailscale, 'https_port': https_port}
        config_file.write_text(json.dumps(config))
        shutil.copyfile(__file__, STATE / 'ota-install.py')  # never run a job from a checkout
        subprocess.run(['/bin/launchctl', 'remove', LABEL], capture_output=True)
        log = str(STATE / 'server.log')
        subprocess.run(['/bin/launchctl', 'submit', '-l', LABEL, '-o', log, '-e', log, '--',
                        sys.executable, str(STATE / 'ota-install.py'), 'serve'], check=True)
        for _ in range(20):
            if healthy(port):
                break
            time.sleep(0.5)
        else:
            raise SystemExit(f'the install page server did not start; see {log}')
    subprocess.run([tailscale, 'serve', '--bg', f'--https={https_port}', '--set-path', PATH,
                    f"http://127.0.0.1:{config['port']}"], check=True, capture_output=True)
    for _ in range(30):
        try:
            if urllib.request.urlopen(f'{base}/', timeout=5).status == 200:
                return
        except OSError:
            pass
        time.sleep(1)
    raise SystemExit(f'the install page never came up at {base}/ (tailscale serve failed?)')


def main(argv):
    if argv[1:2] == ['serve']:
        return serve(json.loads((STATE / 'config.json').read_text()))
    if len(argv) != 2:
        raise SystemExit('usage: ota-install.py <path/to/App.ipa>')
    ipa = Path(argv[1])
    if not ipa.is_file():
        raise SystemExit(f'no such file: {ipa}')
    tailscale = shutil.which('tailscale') or sys.exit('tailscale CLI not found')
    https_port = os.environ.get('OTA_HTTPS_PORT', '443')
    base = tailnet_base(tailscale, https_port)
    STATE.mkdir(parents=True, exist_ok=True)
    with open(STATE / 'lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        prune(STATE / 'www', time.time())
        entry = add(ipa, STATE / 'www', base, time.time())
        ensure_page(tailscale, https_port, base)
    hours = TTL / 3600
    print(f'install page: {base}/')
    print(f"open it in Safari on the phone (tailnet connected) and tap Install - "
          f"{entry['title']} {entry['version']}, listed for {hours:g}h")


if __name__ == '__main__':
    main(sys.argv)
