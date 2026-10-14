import hashlib
import io
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
import updater


def package(version='2.2.1', extra=None):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as z:
        for name in updater.FILES:
            z.writestr(name, json.dumps({'version': version, 'bootstrap': 1}) if name == 'package.json' else '# valid Python\n' if name.endswith('.py') else 'test')
        if extra:
            z.writestr(*extra)
    return stream.getvalue()


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.data = self.root / 'data'
        self.data.mkdir()
        (self.data / 'tools.json').write_text('[{"private":"keep exact bytes"}]')
        (self.data / 'integration.py').write_text('# personal code')
        self.external = self.root / 'private-catalog.py'
        self.external.write_text('# personal catalog')
        self.restart = Mock()
        self.manager = updater.Manager(self.data, '2.2.0', self.restart, SimpleNamespace(backup_paths=lambda: [self.external]))
        self.raw = package()
        self.checksum = hashlib.sha256(self.raw).hexdigest() + '  LocalWorkbench-2.2.1-runtime.zip\n'

    def tearDown(self):
        self.temp.cleanup()

    def fetch(self, url, limit):
        return self.checksum.encode() if url.endswith('SHA256SUMS.txt') else self.raw

    def install(self):
        with patch.object(updater, 'fetch', side_effect=self.fetch), patch.object(updater.subprocess, 'run', return_value=SimpleNamespace(stdout='{"version":"2.2.1","ready":true}\n')), patch.object(updater.time, 'sleep'):
            self.manager.install('2.2.1', ['photopin'])

    def test_success_keeps_config_and_backs_up_external_catalog_and_favorites(self):
        self.install()
        self.assertEqual(json.loads((self.data/'updates/current.json').read_text()), {'version':'2.2.1'})
        self.assertEqual((self.data/'tools.json').read_text(), '[{"private":"keep exact bytes"}]')
        self.assertEqual(self.external.read_text(), '# personal catalog')
        backup=Path(self.manager.status()['backup'])
        self.assertEqual((backup/'tools.json').read_bytes(), (self.data/'tools.json').read_bytes())
        self.assertEqual(json.loads((backup/'browser-favorites.json').read_text()), ['photopin'])
        self.assertEqual((backup/'integration/0/private-catalog.py').read_text(), '# personal catalog')
        self.restart.assert_called_once()

    def test_checksum_failure_never_switches_or_restarts(self):
        self.checksum='0'*64+'  LocalWorkbench-2.2.1-runtime.zip\n'
        self.install()
        self.assertEqual(self.manager.status()['phase'],'error')
        self.assertFalse((self.data/'updates/current.json').exists())
        self.restart.assert_not_called()

    def test_path_traversal_and_duplicate_entries_rejected(self):
        for extra in [('../outside','bad'), ('version.py','bad')]:
            with self.assertRaises(ValueError):
                updater.extract_runtime(package(extra=extra), self.root/'stage', '2.2.1')
        self.assertFalse((self.root/'outside').exists())

    def test_restart_failure_restores_previous_pointer(self):
        updates=self.data/'updates';updates.mkdir()
        old=b'{"version":"2.1.1"}'
        (updates/'current.json').write_bytes(old)
        self.restart.side_effect=OSError('restart failed')
        self.install()
        self.assertEqual((updates/'current.json').read_bytes(),old)
        self.assertEqual(self.manager.status()['phase'],'error')

    def test_preflight_failure_leaves_current_version(self):
        with patch.object(updater,'fetch',side_effect=self.fetch),patch.object(updater.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['test'])):
            self.manager.install('2.2.1',[])
        self.assertFalse((self.data/'updates/current.json').exists())
        self.restart.assert_not_called()

    def test_process_lock_is_not_removed_by_competing_update(self):
        lock=self.data/'updates/install.lock';lock.parent.mkdir(parents=True)
        handle=updater.acquire_lock(lock)
        try:
            self.install()
            self.assertEqual(self.manager.status()['phase'],'error')
            self.restart.assert_not_called()
            with self.assertRaises(ValueError):updater.acquire_lock(lock)
        finally:handle.close()
        updater.acquire_lock(lock).close()

    def test_requires_checked_version_and_rejects_downgrade(self):
        with self.assertRaises(ValueError):self.manager.start('2.2.1',[])
        self.manager.state.update(available=True,latest='2.1.1')
        with self.assertRaises(ValueError):self.manager.start('2.1.1',[])

    def test_manifest_only_accepts_supported_versions_and_constructs_fixed_repo_url(self):
        with patch.object(updater,'fetch',return_value=json.dumps({'schema':1,'version':'2.10.0','bootstrap':1,'url':'https://evil.example'}).encode()):
            release=updater.latest_release()
            self.assertEqual(release['version'],'2.10.0')
            self.assertEqual(release['url'],'https://github.com/Tyler9169/local-workbench/releases/tag/v2.10.0')
        with patch.object(updater,'fetch',return_value=b'{"schema":1,"version":"../bad","bootstrap":1}'):
            with self.assertRaises(ValueError):updater.latest_release()
        self.assertGreater(updater.version_tuple('2.10.0'),updater.version_tuple('2.9.0'))

    def test_network_failure_is_reported_without_mutation(self):
        with patch.object(updater,'latest_release',side_effect=OSError('offline')):
            result=self.manager.check()
        self.assertEqual(result['phase'],'error')
        self.assertFalse(result['available'])
        self.assertFalse((self.data/'updates').exists())

if __name__ == '__main__':unittest.main()
