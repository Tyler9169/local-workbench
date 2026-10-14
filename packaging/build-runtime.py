"""Build the exact runtime allowlist; excludes all personal data and launchers."""
import hashlib
import json
import sys
import zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from version import VERSION
from updater import FILES
output = ROOT / 'releases'
output.mkdir(exist_ok=True)
package = output / f'LocalWorkbench-{VERSION}-runtime.zip'
with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(FILES):
        content = json.dumps({'version': VERSION, 'bootstrap': 1}).encode() if name == 'package.json' else (ROOT / name).read_bytes()
        archive.writestr(name, content)
files = [output / 'PhotoPin-1.1.0-macOS-arm64.zip', output / 'FrameRecorder-1.2.2-macOS-arm64.zip', package, output / f'LocalWorkbench-{VERSION}-macOS-arm64.dmg', output / 'PhotoPin-1.1.0-macOS-arm64.dmg', output / 'FrameRecorder-1.2.2-macOS-arm64.dmg']
(output / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in files if p.exists()))
print(package)
