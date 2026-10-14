"""Verified runtime updates. This module never replaces personal configuration."""
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

REPO = 'Tyler9169/local-workbench'
API = 'https://raw.githubusercontent.com/' + REPO + '/main/update.json'
FILES = {'app_server.py', 'updater.py', 'discovery.py', 'version.py', 'dist/index.html',
         'dist/app.js', 'dist/style.css', 'dist/favicon.svg', 'package.json'}
ACTIVE = {'downloading', 'verifying', 'backing_up', 'installing', 'restarting'}


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d+\.\d+\.\d+', value):
        raise ValueError('版本号无效。')
    return tuple(map(int, value.split('.')))


def fetch(url, limit):
    request = urllib.request.Request(url, headers={'User-Agent': 'LocalWorkbench-Updater', 'Accept': 'application/json' if url == API else 'application/octet-stream'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                data = response.read(limit + 1)
            if len(data) > limit:
                raise ValueError('更新文件超过允许大小。')
            return data
        except urllib.error.HTTPError as exc:
            if attempt == 2 or exc.code not in (408, 429, 500, 502, 503, 504):
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 2:
                raise
        time.sleep(attempt + 1)


def acquire_lock(path):
    handle = path.open('a+b')
    try:
        if os.name == 'nt':
            import msvcrt
            handle.write(b'0'); handle.flush(); handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return handle
    except OSError:
        handle.close()
        raise ValueError('另一个工作台正在更新，请稍候。')


def latest_release():
    release = json.loads(fetch(API, 8192))
    if not isinstance(release, dict) or release.get('schema') != 1:
        raise ValueError('更新清单格式不受支持。')
    version = release.get('version')
    version_tuple(version)
    if release.get('bootstrap') != 1:
        raise ValueError('此版本需要安装新版安装包，请从下载页更新。')
    return dict(version=version, prerelease=bool(release.get('prerelease')),
                asset=f'LocalWorkbench-{version}-runtime.zip',
                url=f'https://github.com/{REPO}/releases/tag/v{version}')


def extract_runtime(raw, destination, version):
    import io
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries = archive.infolist()
        if len(entries) != len(FILES) or {i.filename for i in entries} != FILES:
            raise ValueError('更新包文件列表不符合要求。')
        if sum(i.file_size for i in entries) > 8 * 1024 * 1024:
            raise ValueError('更新包解压大小异常。')
        for info in entries:
            if stat.S_ISLNK(info.external_attr >> 16) or info.is_dir():
                raise ValueError('更新包包含不允许的链接。')
            path = destination / info.filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(archive.read(info))
    manifest = json.loads((destination / 'package.json').read_text())
    if manifest.get('version') != version or manifest.get('bootstrap') != 1:
        raise ValueError('此版本需要更新安装包，请从下载页安装。')
    for name in FILES:
        if name.endswith('.py'):
            compile((destination / name).read_bytes(), name, 'exec')


class Manager:
    def __init__(self, data, current, restart, integration=None):
        self.data, self.current, self.restart, self.integration = Path(data), current, restart, integration
        self.lock = threading.RLock()
        self.state = dict(phase='idle', current=current, latest=None, available=False, message='点击检查更新。')

    def status(self):
        with self.lock:
            return dict(self.state)

    def set_state(self, phase, message, **extra):
        with self.lock:
            self.state.update(phase=phase, message=message, **extra)

    def check(self):
        with self.lock:
            if self.state['phase'] in ACTIVE or self.state['phase'] == 'checking':
                return dict(self.state)
            self.state.update(phase='checking', message='正在检查 GitHub 更新…')
        try:
            release = latest_release()
            available = version_tuple(release['version']) > version_tuple(self.current)
            self.set_state('available' if available else 'current', '发现新版本。' if available else '已是最新版本。',
                           latest=release['version'], available=available, prerelease=release['prerelease'], releaseUrl=release['url'])
        except Exception as exc:
            self.set_state('error', '检查失败，请检查网络后重试。', detail=str(exc)[:240], available=False)
        return self.status()

    def start(self, version, favorites):
        version_tuple(version)
        if not isinstance(favorites, list) or len(favorites) > 500 or any(not isinstance(v, str) or not re.fullmatch(r'[a-z0-9-]{1,64}', v) for v in favorites):
            raise ValueError('收藏数据格式无效。')
        with self.lock:
            if self.state['phase'] in ACTIVE:
                raise ValueError('更新正在进行，请稍候。')
            if not self.state['available'] or version != self.state['latest'] or version_tuple(version) <= version_tuple(self.current):
                raise ValueError('请先检查更新，再选择可用的新版本。')
            self.state.update(phase='downloading', message='正在下载更新…', available=False, target=version)
        threading.Thread(target=self.install, args=(version, favorites), daemon=True).start()
        return self.status()

    def backup(self, favorites):
        backup = self.data / 'updates/backups' / (time.strftime('%Y%m%d-%H%M%S') + '-' + str(time.time_ns()))
        backup.mkdir(parents=True, mode=0o700)
        for path in self.data.iterdir():
            if path.is_file() and path.suffix in ('.json', '.py'):
                shutil.copy2(path, backup / path.name)
        extra = self.integration.backup_paths() if self.integration and hasattr(self.integration, 'backup_paths') else []
        for index, raw in enumerate(extra):
            path = Path(raw)
            if path.is_file():
                folder = backup / 'integration' / str(index)
                folder.mkdir(parents=True)
                shutil.copy2(path, folder / path.name)
        (backup / 'browser-favorites.json').write_text(json.dumps(favorites))
        (backup / 'restore-info.json').write_text(json.dumps({'previousVersion': self.current, 'externalFiles': [str(p) for p in extra]}, ensure_ascii=False, indent=2))
        return backup

    def install(self, version, favorites):
        updates = self.data / 'updates'
        pointer = updates / 'current.json'
        old_pointer = None
        switched = False
        process_lock = None
        created_target = None
        try:
            updates.mkdir(parents=True, exist_ok=True, mode=0o700)
            # The OS releases this lock after a crash as well as a normal restart.
            process_lock = acquire_lock(updates / 'install.lock')
            old_pointer = pointer.read_bytes() if pointer.exists() else None
            base = f'https://github.com/{REPO}/releases/download/v{version}/'
            filename = f'LocalWorkbench-{version}-runtime.zip'
            checksums = fetch(base + 'SHA256SUMS.txt', 65536).decode('utf-8')
            matches = [line.split()[0] for line in checksums.splitlines() if len(line.split()) == 2 and line.split()[1] == filename]
            if len(matches) != 1 or not re.fullmatch(r'[a-fA-F0-9]{64}', matches[0]):
                raise ValueError('找不到更新包的 SHA256 校验值。')
            raw = fetch(base + filename, 8 * 1024 * 1024)
            self.set_state('verifying', '正在校验更新包…')
            if hashlib.sha256(raw).hexdigest() != matches[0].lower():
                raise ValueError('更新包校验失败，当前版本保持不变。')
            with tempfile.TemporaryDirectory(prefix='stage-', dir=updates) as temporary:
                stage = Path(temporary)
                extract_runtime(raw, stage, version)
                command = [sys.executable] + ([] if getattr(sys, 'frozen', False) else [sys.argv[0]]) + ['--validate-update', str(stage)]
                result = subprocess.run(command, env={**os.environ, 'WORKBENCH_DATA_DIR': str(self.data)}, capture_output=True, text=True, timeout=40, check=True)
                if json.loads(result.stdout.strip().splitlines()[-1]) != {'version': version, 'ready': True}:
                    raise ValueError('新版本启动检查未通过。')
                self.set_state('backing_up', '正在备份工具、配置和收藏…')
                backup = self.backup(favorites)
                self.set_state('installing', '正在切换到新版本…', backup=str(backup))
                target = updates / 'versions' / version
                target.parent.mkdir(exist_ok=True)
                if target.exists():
                    raise ValueError('此版本目录已存在，请检查更新备份后重试。')
                shutil.copytree(stage, target)
                created_target = target
                if old_pointer is not None:
                    (updates / 'previous.json').write_bytes(old_pointer)
                elif (updates / 'previous.json').exists():
                    (updates / 'previous.json').unlink()
                pending = updates / 'current.tmp'
                pending.write_text(json.dumps({'version': version}))
                pending.replace(pointer)
                switched = True
            self.set_state('restarting', '更新完成，正在重新连接工作台…')
            # Allow the HTTP response and progress UI to reach the browser before exec.
            time.sleep(1)
            process_lock.close()
            process_lock = None
            self.restart()
        except Exception as exc:
            if switched:
                if old_pointer is None:
                    pointer.unlink(missing_ok=True)
                else:
                    pointer.write_bytes(old_pointer)
            if created_target is not None:
                shutil.rmtree(created_target, ignore_errors=True)
            self.set_state('error', '更新未完成，原工具、配置和当前版本已保留。', detail=str(exc)[:240])
        finally:
            if process_lock is not None:
                process_lock.close()
