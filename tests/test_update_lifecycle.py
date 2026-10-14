"""Real subprocess restart test with a deterministic downloaded release fixture."""
import hashlib
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LifecycleTests(unittest.TestCase):
    @unittest.skipIf(os.name == 'nt', 'POSIX process replacement test; installer targets macOS')
    def test_update_restarts_on_same_port_and_preserves_user_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            data = base / 'data'; data.mkdir()
            tools = '[{"id":"personal","name":"我的工具","category":"日常工具","type":"url","target":"https://example.com","description":"保留"}]'
            (data/'tools.json').write_text(tools,encoding='utf-8')
            raw=io.BytesIO()
            names=['app_server.py','updater.py','discovery.py','version.py','dist/index.html','dist/app.js','dist/style.css','dist/favicon.svg']
            with zipfile.ZipFile(raw,'w',zipfile.ZIP_DEFLATED) as z:
                for name in names:
                    z.writestr(name,"VERSION = '99.0.0'\n" if name=='version.py' else (ROOT/name).read_bytes())
                z.writestr('package.json',json.dumps({'version':'99.0.0','bootstrap':1}))
            package=base/'fixture.zip';package.write_bytes(raw.getvalue())
            with socket.socket() as sock:
                sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
            script=base/'launcher.py'
            script.write_text(f'''import sys, hashlib
from pathlib import Path
sys.path.insert(0,{str(ROOT)!r})
import server
raw=Path({str(package)!r}).read_bytes()
server.updater.latest_release=lambda:dict(version='99.0.0',prerelease=True,url='https://github.com/Tyler9169/local-workbench/releases/tag/v99.0.0')
server.updater.fetch=lambda url,limit:(hashlib.sha256(raw).hexdigest()+'  LocalWorkbench-99.0.0-runtime.zip\\n').encode() if url.endswith('SHA256SUMS.txt') else raw
server.ThreadingHTTPServer(('127.0.0.1',{port}),server.Handler).serve_forever()
''',encoding='utf-8')
            env={**os.environ,'WORKBENCH_DATA_DIR':str(data)}
            process=subprocess.Popen([sys.executable,str(script)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            url=f'http://127.0.0.1:{port}'
            def get(path):
                with urllib.request.urlopen(url+path,timeout=1) as r:return json.load(r)
            def post(path,body):
                req=urllib.request.Request(url+path,data=json.dumps(body).encode(),headers={'Origin':url,'X-Workbench':'1','Content-Type':'application/json'})
                with urllib.request.urlopen(req,timeout=3) as r:return json.load(r)
            def wait_version(version):
                for _ in range(150):
                    if process.poll() is not None:
                        self.fail(process.stderr.read().decode())
                    try:
                        if get('/api/health')['version']==version:return
                    except OSError:pass
                    time.sleep(.1)
                self.fail('Update restart timed out')
            try:
                wait_version(__import__('version').VERSION)
                self.assertTrue(post('/api/update/check',{})['available'])
                post('/api/update/install',{'version':'99.0.0','favorites':['personal']})
                wait_version('99.0.0')
                self.assertEqual((data/'tools.json').read_text(encoding='utf-8'),tools)
                self.assertIn('personal',[t['id'] for t in get('/api/tools')['tools']])
                backups=list((data/'updates/backups').glob('*/browser-favorites.json'))
                self.assertEqual(len(backups),1)
                self.assertEqual(json.loads(backups[0].read_text()),['personal'])
            finally:
                process.terminate()
                process.communicate(timeout=10)

if __name__=='__main__':unittest.main()
