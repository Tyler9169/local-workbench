import http.client
import json
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
        self.http = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.entry = dict(id='example', name='示例', type='url', category='日常工具', target='https://example.com', description='用途')

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.data_patch.stop()
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
        for route in ('/api/tools', '/api/delete', '/api/action'):
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

    def test_oversized_and_wrong_content_type(self):
        self.assertEqual(self.request('/api/tools', {'text': 'a' * 17000})[0], 413)
        self.assertEqual(self.request('/api/tools', self.entry, {'Content-Type': 'text/plain'})[0], 415)

if __name__ == '__main__':
    unittest.main()
