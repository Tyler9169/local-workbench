"""Build a self-contained Apple Silicon app from an explicit public-source allowlist."""
from pathlib import Path
import shutil, subprocess, plistlib, json, os
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build'; APP=OUT/'留刻计时器.app'
if APP.exists():shutil.rmtree(APP)
shutil.copytree(ROOT/'node_modules/electron/dist/Electron.app', APP, symlinks=True)
resources=APP/'Contents/Resources'; source=resources/'app'; source.mkdir()
for name in ['dist','desktop','server.mjs','runtime.mjs','sounds.mjs','data-path.mjs']:
    p=ROOT/name
    if p.is_dir():shutil.copytree(p,source/name)
    else:shutil.copy2(p,source/name)
(source/'package.json').write_text(json.dumps(dict(name='stage-timer',version='1.0.0',type='module',main='desktop/launcher.mjs')))
node=Path(shutil.which('node')).resolve();shutil.copy2(node,resources/'node')
shutil.copy2(node.parent.parent/'LICENSE',resources/'NODE-LICENSE.txt')
for name in ['LICENSE','LICENSES.chromium.html']:
    shutil.copy2(ROOT/'node_modules/electron/dist'/name,resources/name)
plist=APP/'Contents/Info.plist';info=plistlib.loads(plist.read_bytes())
info.update(CFBundleName='留刻计时器',CFBundleDisplayName='留刻计时器',CFBundleIdentifier='local.tyler.stagetimer',CFBundleShortVersionString='1.0.0',CFBundleVersion='100',LSMinimumSystemVersion='13.5',NSAppleEventsUsageDescription='用于回到已经打开的留刻计时器网页。')
plist.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--deep','--sign','-',str(APP)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True)
stage=OUT/'dmg';stage.mkdir(exist_ok=True)
if (stage/APP.name).exists():shutil.rmtree(stage/APP.name)
shutil.copytree(APP,stage/APP.name,symlinks=True)
if not (stage/'Applications').is_symlink():(stage/'Applications').symlink_to('/Applications')
shutil.copy2(ROOT/'packaging/安装说明.txt',stage/'安装说明.txt')
release=ROOT/'releases';release.mkdir(exist_ok=True)
subprocess.run(['hdiutil','create','-volname','留刻计时器','-srcfolder',str(stage),'-ov','-format','UDZO',str(release/'StageTimer-1.0.0-macOS-arm64.dmg')],check=True)
print(APP)
