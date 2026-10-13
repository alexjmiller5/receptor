import contextlib
import importlib.util
import io
import plistlib
import tempfile
import threading
import unittest
import urllib.request
import zipfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('ota_install', Path(__file__).with_name('ota-install.py'))


def load():
    module = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(module)
    return module


def make_ipa(path, bundle='com.example.app', version='1.0', build='1', name='Example & Co'):
    info = plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': version,
                           'CFBundleVersion': build, 'CFBundleDisplayName': name})
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('Payload/Example.app/Info.plist', info)
        z.writestr('Payload/Example.app/Example', b'binary')
    return path


class ShelfTests(unittest.TestCase):
    def setUp(self):
        self.ota = load()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.tmp = Path(self.directory.name)
        self.www = self.tmp / 'www'
        self.base = 'https://host.example.ts.net/install'

    def add(self, now=1000.0, **kw):
        ipa = make_ipa(self.tmp / f"{kw.get('bundle', 'x')}-{kw.get('version', '1')}.ipa", **kw)
        return self.ota.add(ipa, self.www, self.base, now)

    def test_add_publishes_ipa_manifest_and_entry(self):
        entry = self.add(version='1.2')
        folder = self.www / 'com.example.app'
        self.assertTrue((folder / 'app.ipa').is_file())
        manifest = plistlib.loads((folder / 'manifest.plist').read_bytes())
        item = manifest['items'][0]
        # No query strings: iOS ignores an install link whose manifest URL carries one (the
        # phone loads the page but never fetches the manifest), so both URLs stay plain.
        self.assertEqual(item['assets'][0]['url'], f'{self.base}/com.example.app/app.ipa')
        self.assertEqual(item['metadata']['bundle-identifier'], 'com.example.app')
        self.assertEqual(item['metadata']['bundle-version'], '1.2')
        self.assertEqual(entry['title'], 'Example & Co')
        self.assertEqual([e['bundle'] for e in self.ota.entries(self.www)], ['com.example.app'])

    def test_newer_build_of_the_same_app_replaces_its_entry(self):
        self.add(now=1000.0, version='1.0')
        self.add(now=2000.0, version='1.1')
        listed = self.ota.entries(self.www)
        self.assertEqual([(e['bundle'], e['version'], e['added']) for e in listed],
                         [('com.example.app', '1.1', 2000.0)])

    def test_index_lists_every_app_newest_first_with_escaped_titles(self):
        self.add(now=1000.0, bundle='com.example.one', name='One')
        self.add(now=2000.0, bundle='com.example.two', name='Two <beta>')
        html = self.ota.render_index(self.ota.entries(self.www), self.base)
        self.assertLess(html.index('Two &lt;beta&gt;'), html.index('One'))
        self.assertEqual(html.count('itms-services://?action=download-manifest'), 2)
        self.assertIn(f'url={self.base}/com.example.two/manifest.plist">', html)
        self.assertIn('background:#0a84ff', html)
        # The build number tells two builds of one version apart on the phone.
        self.assertIn('<h2>One 1.0 (1)</h2>', html)

    def test_empty_index_says_so(self):
        self.assertIn('Nothing to install', self.ota.render_index([], self.base))

    def test_prune_drops_entries_older_than_the_ttl(self):
        self.add(now=0.0, bundle='com.example.old')
        self.add(now=100_000.0, bundle='com.example.new')
        removed = self.ota.prune(self.www, now=0.0 + self.ota.TTL + 1)
        self.assertEqual(removed, ['com.example.old'])
        self.assertFalse((self.www / 'com.example.old').exists())
        self.assertEqual([e['bundle'] for e in self.ota.entries(self.www)], ['com.example.new'])

    def test_rejects_a_file_that_is_not_an_ipa(self):
        bogus = self.tmp / 'bogus.ipa'
        with zipfile.ZipFile(bogus, 'w') as z:
            z.writestr('readme.txt', 'no')
        with self.assertRaises(SystemExit):
            self.ota.add(bogus, self.www, self.base, 0.0)


class ServerTests(unittest.TestCase):
    def test_server_serves_the_live_index_files_and_health(self):
        ota = load()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        tmp = Path(directory.name)
        www = tmp / 'www'
        base = 'https://host.example.ts.net/install'
        ota.add(make_ipa(tmp / 'a.ipa'), www, base, 0.0)  # already expired at serve time
        server = ota.make_server(www, base, 0)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_address[1]}'
        try:
            self.assertEqual(urllib.request.urlopen(f'{url}/healthz').read(), b'ota-install')
            self.assertIn(b'Nothing to install', urllib.request.urlopen(f'{url}/').read())
            ota.add(make_ipa(tmp / 'b.ipa', name='Fresh'), www, base, ota.time.time())
            self.assertIn(b'Fresh', urllib.request.urlopen(f'{url}/').read())
            log = io.StringIO()
            with contextlib.redirect_stderr(log):
                request = urllib.request.Request(f'{url}/com.example.app/manifest.plist?v=1',
                                                 headers={'User-Agent': 'com.apple.appstored/1.0 iOS/26.0'})
                manifest = urllib.request.urlopen(request).read()
            self.assertIn(b'software-package', manifest)
            # Each request is logged with its client, so a failed phone install shows how far it got.
            self.assertIn('GET /com.example.app/manifest.plist?v=1 200', log.getvalue())
            self.assertIn('com.apple.appstored/1.0 iOS/26.0', log.getvalue())
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    unittest.main()
