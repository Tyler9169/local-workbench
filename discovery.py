"""Discover only our two known macOS bundles; no indexing or recursive disk scan."""
import os
import plistlib
import sys
from pathlib import Path

APP_ROOTS = (Path.home() / 'Applications', Path('/Applications'))
KNOWN = {
    'local.tyler.photopin': ('auto-photopin', '照片置顶', '日常工具', '图片悬浮、位置锁定与缩放。'),
    'local.tyler.framerecorder': ('auto-framerecorder', '框录', '影音创作', '区域截图与录屏，系统声音和麦克风独立开关。'),
}


def bundle_id(path):
    try:
        with (Path(path) / 'Contents/Info.plist').open('rb') as f:
            info = plistlib.load(f)
        if not isinstance(info, dict):
            return None
        executable = info.get('CFBundleExecutable', '')
        if not isinstance(executable, str) or not executable or Path(executable).name != executable:
            return None
        binary = Path(path) / 'Contents/MacOS' / executable
        if not binary.is_file() or not os.access(binary, os.X_OK):
            return None
        identity = info.get('CFBundleIdentifier')
        return identity if isinstance(identity, str) else None
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException):
        return None


def discover():
    if sys.platform != 'darwin':
        return []
    found = {}
    for root in APP_ROOTS:
        try:
            candidates = sorted(root.glob('*.app'))
        except OSError:
            continue
        for path in candidates:
            identity = bundle_id(path)
            if identity not in KNOWN or identity in found:
                continue
            id, name, category, description = KNOWN[identity]
            found[identity] = dict(id=id, name=name, category=category, description=description,
                                   type='app', target=str(path.resolve()))
    return list(found.values())
