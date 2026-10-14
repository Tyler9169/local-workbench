"""Compile the shipped validator and exercise native replacement/rollback in isolated apps."""
import os, plistlib, subprocess, tempfile, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout
with tempfile.TemporaryDirectory(prefix='native-updater-test-') as temporary:
    work = Path(temporary)
    def archive(name, entries):
        with zipfile.ZipFile(work / (name + '.zip'), 'w') as z:
            for entry, content in entries: z.writestr(entry, content)
    archive('good', [('Test.app/Contents/a', 'data')])
    archive('traversal', [('Test.app/../../escape', '')])
    archive('duplicate', [('Test.app/a', ''), ('Test.app/a', '')])
    archive('wrongroot', [('Other.app/a', '')])
    link = zipfile.ZipInfo('Test.app/link'); link.create_system = 3; link.external_attr = 0o120777 << 16
    archive('symlink', [(link, '/tmp')])
    raw = (work / 'good.zip').read_bytes()
    altered = raw.replace(b'Test.app/Contents/a', b'Test.app/Contents/b', 1)
    (work / 'localmismatch.zip').write_bytes(altered)
    (work / 'truncated.zip').write_bytes(raw[:-8])
    main = work / 'main.swift'; main.write_text((ROOT / 'tests/native/validation.swift').read_text())
    run('swiftc', str(ROOT / 'tools/shared/NativeUpdater.swift'), str(main), '-o', str(work / 'validate'), '-framework', 'AppKit')
    print(run(str(work / 'validate'), str(work), str(ROOT / "releases")).strip())
    # Standalone LaunchServices app implementing the startup acknowledgement contract.
    source = work / 'fixture.swift'
    source.write_text('''import Foundation
let a = CommandLine.arguments
if let i = a.firstIndex(of: "--native-update-token"), a.count > i+1,
   let support = Bundle.main.object(forInfoDictionaryKey: "TestSupport") as? String {
    try! Data("ready".utf8).write(to: URL(fileURLWithPath: support + "/" + a[i+1] + ".ready"))
}
''')
    run('swiftc', str(source), '-o', str(work / 'Fixture'))
    helper = work / 'install.sh'
    helper.write_text((ROOT / 'tools/shared/install-update.sh').read_text().replace('i<60', 'i<3'))
    for succeeds in [True, False]:
        folder = work / ('success' if succeeds else 'rollback'); folder.mkdir()
        support = folder / 'support'; support.mkdir()
        settings = support / 'existing-settings.plist'; settings.write_bytes(b'original-settings')
        original = folder / 'Test.app'; (original / 'Contents/MacOS').mkdir(parents=True)
        stage = folder / 'stage'; new = stage / 'Application.app'; (new / 'Contents/MacOS').mkdir(parents=True)
        for app, version in [(original, '1.0'), (new, '2.0')]:
            import shutil
            shutil.copy(work / 'Fixture', app / 'Contents/MacOS/Fixture')
            info = dict(CFBundleName='UpdateTest', CFBundleIdentifier='local.workbench.updatetest.' + folder.name, CFBundleExecutable='Fixture', CFBundlePackageType='APPL', CFBundleVersion=version, LSUIElement=True)
            if succeeds and app == new: info['TestSupport'] = str(support)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            run('codesign', '--force', '--sign', '-', str(app))
        result = subprocess.run(['/bin/bash', str(helper), '99999999', str(original), str(stage), str(support), 'fixture-token'], capture_output=True, text=True)
        expected = '2.0' if succeeds else '1.0'
        assert plistlib.loads((original/'Contents/Info.plist').read_bytes())['CFBundleVersion'] == expected, result.stderr
        assert result.returncode == (0 if succeeds else 1), result.stderr
        assert settings.read_bytes() == b'original-settings'
        assert not Path(str(original)+'.update-lock').exists()
        if succeeds: assert Path(str(original)+'.backup-fixture-token').exists()
        else: assert (stage/'Failed.app').exists() and (support/'last-error.txt').exists()
        print('Real native helper:', folder.name, 'passed; settings preserved')
