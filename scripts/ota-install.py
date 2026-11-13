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

import base64
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


# One SVG master; PNGs are Quick Look renders, kept inline so publishers stay self-contained.
ICON_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 64 64">
<!-- Composed from tabler:device-mobile and tabler:download (Iconify).
MIT License

Copyright (c) 2020-2026 Paweł Kuna

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-->
<g transform="translate(-8 1) scale(2.6)" stroke="#67e8f9" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<path fill="#0f172a" d="M6 5a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2v-14"/>
<path fill="none" d="M11 4h2"/>
</g>
<circle cx="44" cy="43" r="19" fill="#67e8f9" stroke="none"/>
<g transform="translate(27.8 26.8) scale(1.35)" fill="none" stroke="#0f172a" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">
<path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2 -2v-2"/>
<path d="M7 11l5 5l5 -5"/>
<path d="M12 4l0 12"/>
</g>
</svg>"""
ICON_PNGS = {
    'apple-touch-icon.png': base64.b64decode(
        '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'
        'xoM3cBiQAAAAAElFTkSuQmCC'
    ),
    'icon-192.png': base64.b64decode(
        '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'
    ),
    'icon-512.png': base64.b64decode(
        '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'
    ),
}


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
            f'<link rel="icon" type="image/svg+xml" href="{html.escape(base)}/favicon.svg">'
            f'<link rel="apple-touch-icon" sizes="180x180" href="{html.escape(base)}/apple-touch-icon.png">'
            f'<link rel="icon" type="image/png" sizes="192x192" href="{html.escape(base)}/icon-192.png">'
            f'<link rel="icon" type="image/png" sizes="512x512" href="{html.escape(base)}/icon-512.png">'
            '<title>Install</title><body style="font:20px -apple-system;padding:48px 24px;text-align:center">'
            f'{sections}</body>')


def make_server(www, base, port):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kw):
            super().__init__(*args, directory=str(www), **kw)

        def send_body(self, body, kind):
            data = body if isinstance(body, bytes) else body.encode()
            self.send_response(200)
            self.send_header('Content-Type', kind)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            route = self.path.split('?')[0]
            if route == '/favicon.svg':
                return self.send_body(ICON_SVG, 'image/svg+xml')
            if route.lstrip('/') in ICON_PNGS:
                return self.send_body(ICON_PNGS[route.lstrip('/')], 'image/png')
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
