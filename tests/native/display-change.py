"""macOS regression test: display notifications must not reopen a dismissed panel."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='frame-display-test-') as temp:
    work=Path(temp)
    source=(root/'tools/framerecorder/Sources/main.swift').read_text()
    source=source[:source.rindex('MainActor.assumeIsolated {')]+(root/'tests/native/display-change.swift').read_text()
    # Keep fixture status output separate from the installed application's data.
    source=source.replace('appendingPathComponent("框录")','appendingPathComponent("FrameRecorderDisplayRegression")')
    (work/'main.swift').write_text(source)
    subprocess.run(['swiftc',str(work/'main.swift'),str(root/'tools/framerecorder/Sources/Geometry.swift'),str(root/'tools/shared/NativeUpdater.swift'),'-o',str(work/'validate'),'-framework','AppKit','-framework','ScreenCaptureKit','-framework','AVFoundation','-framework','Carbon'],check=True)
    subprocess.run([str(work/'validate')],check=True)
