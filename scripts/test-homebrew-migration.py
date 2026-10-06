"""Exercise the actual transition without touching a real Homebrew installation."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('migrate-homebrew.sh')


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='receptor-migration-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = self.root / 'brew prefix'
        self.bin = self.prefix / 'bin'
        self.bin.mkdir(parents=True)
        self.receipt = self.prefix / 'Caskroom/receptor/.metadata/INSTALL_RECEIPT.json'
        self.log = self.root / 'brew.log'
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        TEST_LOG=str(self.log), TEST_RECEIPT=str(self.receipt))
        self.write_command('pgrep', '#!/bin/sh\nexit "${TEST_RUNNING:-1}"\n')
        self.write_command('brew', '''#!/bin/sh
printf '%s\\n' "$*" "$HOMEBREW_NO_AUTO_UPDATE" "$HOMEBREW_NO_INSTALL_CLEANUP" "$HOMEBREW_NO_AUTOREMOVE" > "$TEST_LOG"
if [ "${TEST_FAILURE:-0}" != 0 ]; then exit "$TEST_FAILURE"; fi
if [ "${TEST_KEEP_RECEIPT:-0}" = 0 ]; then /bin/rm "$TEST_RECEIPT"; fi
''')

    def write_command(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def install_receipt(self, **changes):
        self.receipt.parent.mkdir(parents=True)
        data = {'source': {'tap': 'alexjmiller5/tap', 'version': '2.0.1'},
                'uninstall_flight_blocks': False,
                'uninstall_artifacts': [{'app': ['Receptor.app']}]}
        data.update(changes)
        self.receipt.write_text(json.dumps(data))

    def run_migration(self):
        return subprocess.run(['bash', str(SCRIPT), str(self.prefix)],
                              env=self.env, text=True, capture_output=True)

    def test_absent_is_noop(self):
        self.assertEqual(self.run_migration().returncode, 0)
        self.assertFalse(self.log.exists())

    def test_exact_receipt_uninstalls_without_zap_or_force(self):
        self.install_receipt()
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(),
                         ['uninstall --cask alexjmiller5/tap/receptor', '1', '1', '1'])
        self.assertFalse(self.receipt.exists())

    def test_running_refuses_without_uninstall(self):
        self.install_receipt()
        self.env['TEST_RUNNING'] = '0'
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse(self.log.exists())
        self.assertTrue(self.receipt.exists())

    def test_uninstall_failure_propagates(self):
        self.install_receipt()
        self.env['TEST_FAILURE'] = '77'
        self.assertEqual(self.run_migration().returncode, 77)
        self.assertTrue(self.receipt.exists())

    def test_unremoved_receipt_refuses_cleanup(self):
        self.install_receipt()
        self.env['TEST_KEEP_RECEIPT'] = '1'
        self.assertNotEqual(self.run_migration().returncode, 0)

    def test_unknown_receipt_refuses(self):
        self.install_receipt(source={'tap': 'unrelated/tap'})
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse(self.log.exists())

    def test_extra_removal_hooks_refuse(self):
        self.install_receipt(uninstall_artifacts=[{'app': ['Receptor.app']}, {'zap': ['private-state']}])
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse(self.log.exists())

    def test_broken_receipt_refuses(self):
        self.install_receipt()
        self.receipt.write_text('{}')
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse(self.log.exists())

    def test_process_inspection_failure_refuses(self):
        self.install_receipt()
        self.env['TEST_RUNNING'] = '2'
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
