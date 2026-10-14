"""Stable bootstrap shared by the source and macOS desktop distributions."""
import importlib
import json
import os
import sys
from pathlib import Path

from version import VERSION as BASE_VERSION
BOOTSTRAP = 1
BASE = Path(__file__).resolve().parent
DATA = Path(os.environ.get('WORKBENCH_DATA_DIR', str(BASE / 'data'))).expanduser().resolve()
os.environ['WORKBENCH_DATA_DIR'] = str(DATA)


def selected_runtime():
    pointer = DATA / 'updates/current.json'
    if not pointer.exists():
        return BASE
    info = json.loads(pointer.read_text())
    import re
    if not isinstance(info, dict) or not re.fullmatch(r'\d+\.\d+\.\d+', info.get('version', '')):
        raise ValueError('更新版本记录无效')
    if tuple(map(int, info['version'].split('.'))) < tuple(map(int, BASE_VERSION.split('.'))):
        return BASE
    path = DATA / 'updates/versions' / info['version']
    if not path.is_dir() or path.is_symlink():
        raise ValueError('更新版本目录缺失')
    return path


def load_runtime():
    # Preflight runs in a separate process, before changing the active version.
    preflight = len(sys.argv) == 3 and sys.argv[1] == '--validate-update'
    try:
        path = Path(sys.argv[2]).resolve() if preflight else selected_runtime()
    except Exception:
        path = recover_runtime()

    sys.path.insert(0, str(path))
    for name in ('discovery', 'updater', 'version', 'app_server'):
        sys.modules.pop(name, None)
    try:
        module = importlib.import_module('app_server')
        if preflight:
            module.load()
            module.catalog(module.load())
            for name in ('index.html', 'app.js', 'style.css', 'favicon.svg'):
                (path / 'dist' / name).read_bytes()
            print(json.dumps({'version': module.VERSION, 'ready': True}), flush=True)
            raise SystemExit(0)
        return module
    except Exception:
        # An import failure falls back without touching user configuration.
        if preflight or path == BASE:
            raise
        sys.path.remove(str(path))
        sys.path.insert(0, str(recover_runtime()))
        for name in ('discovery', 'updater', 'version', 'app_server'):
            sys.modules.pop(name, None)
        return importlib.import_module('app_server')


def recover_runtime():
    pointer = DATA / 'updates/current.json'
    previous = DATA / 'updates/previous.json'
    if pointer.exists():
        pointer.replace(DATA / 'updates/failed-current.json')
    if previous.exists():
        pointer.write_bytes(previous.read_bytes())
        try:
            return selected_runtime()
        except Exception:
            pointer.unlink(missing_ok=True)
    return BASE
