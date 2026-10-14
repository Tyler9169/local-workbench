import http.client
import os
from types import SimpleNamespace
import json
import plistlib
import shutil
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class WorkbenchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.data_patch = patch.object(server, 'DATA', Path(self.temp.name))
        self.data_patch.start()
        self.integration_patch = patch.object(server, 'INTEGRATION', None)
        self.integration_patch.start()
        self.discovery_patch = patch.object(server.discovery, 'APP_ROOTS', ())
        self.discovery_patch.start()
        self.http = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.entry = dict(id='example', name='示例', type='url', category='日常工具', target='https://example.com', description='用途')

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.data_patch.stop()
        self.integration_patch.stop()
        self.discovery_patch.stop()
        self.temp.cleanup()

    def request(self, path, body=None, headers=None):
        port = self.http.server_port
        h = {'Origin': f'http://127.0.0.1:{port}', 'Content-Type': 'application/json', 'X-Workbench': '1'}
        h.update(headers or {})
        c = http.client.HTTPConnection('127.0.0.1', port)
        c.request('POST' if body is not None else 'GET', path, json.dumps(body) if body is not None else None, h)
        r = c.getresponse(); data = r.read(); code = r.status; c.close()
        return code, data

    def test_fresh_install_empty(self):
        code, body = self.request('/api/tools')
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)['tools'], [])

    def test_crud_persists_and_only_deletes_entry(self):
        self.assertEqual(self.request('/api/tools', self.entry)[0], 200)
        self.assertEqual(self.request('/api/tools', {**self.entry, 'name': '修改'})[0], 200)
        self.assertEqual(server.load()[0]['name'], '修改')
        self.assertEqual(self.request('/api/delete', {'id': 'example'})[0], 200)
        self.assertEqual(server.load(), [])

    def test_duplicate_target_rejected(self):
        self.request('/api/tools', self.entry)
        self.assertEqual(self.request('/api/tools', {**self.entry, 'id': 'second'})[0], 400)

    def test_cross_origin_rejected_for_all_writes(self):
        for route in ('/api/tools', '/api/delete', '/api/action', '/api/update/check', '/api/update/install'):
            for origin in ('https://evil.example', 'null', ''):
                self.assertEqual(self.request(route, self.entry, {'Origin': origin})[0], 403)

    def test_host_and_traversal(self):
        self.assertEqual(self.request('/api/tools', headers={'Host': 'evil.example'})[0], 403)
        for path in ('/../server.py', '/data/tools.json', '/.git/config', '/api/tools?x=1'):
            self.assertEqual(self.request(path)[0], 404)

    def test_commands_and_secret_urls_rejected(self):
        for target in ('javascript:alert(1)', 'file:///etc/passwd', 'https://u:p@example.com', 'https://example.com/?token=123', 'http://example.com', 'https://example.com:bad'):
            self.assertEqual(self.request('/api/tools', {**self.entry, 'target': target})[0], 400)
        self.assertEqual(self.request('/api/tools', {**self.entry, 'cmd': 'id'})[0], 400)

    def test_missing_folder_retained_but_cannot_launch(self):
        entry = {**self.entry, 'type': 'folder', 'target': str(Path(self.temp.name) / 'missing')}
        self.assertEqual(self.request('/api/tools', entry)[0], 200)
        self.assertFalse(server.present(server.load()[0])['available'])
        self.assertEqual(self.request('/api/action', {'id': 'example', 'action': 'open'})[0], 400)

    def test_script_cannot_be_registered_or_opened_after_replacement(self):
        p = Path(self.temp.name) / 'folder'; p.mkdir()
        entry = {**self.entry, 'type': 'folder', 'target': str(p)}
        self.request('/api/tools', entry)
        p.rmdir(); p.write_text('script')
        with patch.object(server.subprocess, 'run') as run:
            self.assertEqual(self.request('/api/action', {'id': 'example', 'action': 'open'})[0], 400)
            run.assert_not_called()

    def test_open_only_registered_target(self):
        self.request('/api/tools', self.entry)
        with patch.object(server.webbrowser, 'open', return_value=True) as opener:
            self.assertEqual(self.request('/api/action', {'id': 'example', 'action': 'open'})[0], 200)
            opener.assert_called_once_with('https://example.com')
            self.assertEqual(self.request('/api/action', {'id': 'example', 'action': 'exec'})[0], 400)
            self.assertEqual(self.request('/api/action', {'id': 'example', 'action': 'open', 'cmd': 'id'})[0], 400)

    def test_corrupt_config_never_overwritten(self):
        p = server.DATA / 'tools.json'; p.write_text('{broken')
        self.assertEqual(self.request('/api/tools')[0], 500)
        self.assertEqual(self.request('/api/tools', self.entry)[0], 400)
        self.assertEqual(p.read_text(), '{broken')

    def test_update_endpoints_validate_requests_and_return_progress(self):
        from unittest.mock import Mock
        manager=Mock()
        manager.check.return_value={'phase':'current','current':'2.2.0'}
        manager.status.return_value={'phase':'idle','current':'2.2.0'}
        manager.start.return_value={'phase':'downloading'}
        with patch.object(server,'UPDATE',manager):
            self.assertEqual(self.request('/api/update/status')[0],200)
            self.assertEqual(self.request('/api/update/check',{})[0],200)
            self.assertEqual(self.request('/api/update/check',{'url':'bad'})[0],400)
            self.assertEqual(self.request('/api/update/install',{'version':'2.2.1','favorites':[]})[0],202)
            manager.start.assert_called_once_with('2.2.1',[])
            self.assertEqual(self.request('/api/update/install',{'version':'2.2.1','favorites':[],'url':'bad'})[0],400)

    def test_oversized_and_wrong_content_type(self):
        self.assertEqual(self.request('/api/tools', {'text': 'a' * 17000})[0], 413)
        self.assertEqual(self.request('/api/tools', self.entry, {'Content-Type': 'text/plain'})[0], 415)

class DiscoveryTests(WorkbenchTests):
    def setUp(self):
        super().setUp()
        self.roots = (Path(self.temp.name) / 'user', Path(self.temp.name) / 'system')
        for root in self.roots:
            root.mkdir()
        self.roots_patch = patch.object(server.discovery, 'APP_ROOTS', self.roots)
        self.roots_patch.start()
        self.platform_patch = patch.object(server.discovery, 'sys', SimpleNamespace(platform='darwin'))
        self.platform_patch.start()
        self.server_platform_patch = patch.object(server, 'sys', SimpleNamespace(platform='darwin'))
        self.server_platform_patch.start()

    def tearDown(self):
        self.server_platform_patch.stop()
        self.platform_patch.stop()
        self.roots_patch.stop()
        super().tearDown()

    def app(self, name='Renamed', identity='local.tyler.photopin', root=0):
        app = self.roots[root] / (name + '.app')
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identity, CFBundleExecutable='test')))
        executable = app / 'Contents/MacOS/test'
        executable.write_text('#!/bin/sh\nexit 0\n')
        executable.chmod(0o755)
        return app

    def tools(self):
        code, body = self.request('/api/tools')
        self.assertEqual(code, 200)
        return json.loads(body)['tools']

    def test_install_remove_and_renamed_apps(self):
        self.assertEqual(self.tools(), [])
        photo = self.app()
        self.assertEqual([t['name'] for t in self.tools()], ['照片置顶'])
        frame = self.app('Frame', 'local.tyler.framerecorder')
        self.assertEqual({t['name'] for t in self.tools()}, {'照片置顶', '框录'})
        shutil.rmtree(photo)
        self.assertEqual([t['name'] for t in self.tools()], ['框录'])
        shutil.rmtree(frame)
        self.assertEqual(self.tools(), [])
        self.assertFalse((server.DATA / 'tools.json').exists())

    def test_user_copy_preferred_and_manual_entry_deduplicated(self):
        user = self.app(root=0)
        self.app(root=1)
        self.assertEqual(len(self.tools()), 1)
        self.assertEqual(self.tools()[0]['path'], str(user.resolve()))
        self.request('/api/tools', {**self.entry, 'type': 'app', 'target': str(user)})
        self.assertEqual([t['id'] for t in self.tools()], ['example'])

    def test_invalid_and_unrelated_bundles_ignored(self):
        self.app('Other', 'other.app')
        broken = self.app('Broken')
        (broken / 'Contents/Info.plist').write_bytes(plistlib.dumps(['not a dictionary']))
        missing = self.app('Missing')
        (missing / 'Contents/MacOS/test').unlink()
        if os.name != 'nt':
            nonexec = self.app('Nonexec')
            (nonexec / 'Contents/MacOS/test').chmod(0o644)
        self.assertEqual(self.tools(), [])

    def test_auto_action_resolves_current_install_and_disallows_mutation(self):
        app = self.app()
        with patch.object(server, 'sys', SimpleNamespace(platform='darwin')), patch.object(server.subprocess, 'run') as run:
            self.assertEqual(self.request('/api/action', {'id': 'auto-photopin', 'action': 'open'})[0], 200)
            run.assert_called_once_with(['/usr/bin/open', str(app.resolve())], check=True, timeout=10)
            run.reset_mock()
            shutil.rmtree(app)
            self.assertEqual(self.request('/api/action', {'id': 'auto-photopin', 'action': 'open'})[0], 404)
            run.assert_not_called()
        self.assertEqual(self.request('/api/delete', {'id': 'auto-photopin'})[0], 404)
        self.assertEqual(self.request('/api/tools', {**self.entry, 'id': 'auto-photopin'})[0], 400)

    def test_other_platforms_skip_discovery(self):
        self.app()
        with patch.object(server.discovery, 'sys', SimpleNamespace(platform='linux')):
            self.assertEqual(self.tools(), [])

if __name__ == '__main__':
    unittest.main()
