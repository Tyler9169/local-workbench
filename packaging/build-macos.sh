#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHON="${BUILD_PYTHON:-.venv-build/bin/python}"
VERSION=2.2.3
ARCH="$(uname -m)"
APP="build/macos/本地工作台.app"
"$PYTHON" -m PyInstaller --noconfirm --clean --onedir --hidden-import app_server --hidden-import updater --hidden-import discovery --hidden-import version --hidden-import concurrent.futures --name WorkbenchServer --distpath build/backend --workpath build/pyinstaller --specpath build --add-data "$PWD/dist:dist" desktop.py
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/Workbench.iconset releases
rm -rf "$APP/Contents/Resources/backend"
cp -R build/backend/WorkbenchServer "$APP/Contents/Resources/backend"
xcrun swiftc -O -target "$ARCH-apple-macosx14.0" -framework AppKit packaging/Launcher.swift -o "$APP/Contents/MacOS/WorkbenchLauncher"
xcrun swift packaging/Icon.swift build/Workbench.iconset
iconutil -c icns build/Workbench.iconset -o "$APP/Contents/Resources/Workbench.icns"
"$PYTHON" - "$APP" "$VERSION" <<'PY'
import plistlib,sys
from pathlib import Path
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleName='本地工作台', CFBundleDisplayName='本地工作台', CFBundleIdentifier='io.github.tyler9169.localworkbench', CFBundleExecutable='WorkbenchLauncher', CFBundlePackageType='APPL', CFBundleIconFile='Workbench', CFBundleShortVersionString=sys.argv[2], CFBundleVersion='223', LSMinimumSystemVersion='14.0', LSUIElement=True, NSHighResolutionCapable=True)))
PY
cp -R packaging/licenses "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
STAGE="build/dmg-$ARCH"
mkdir -p "$STAGE"
rm -rf "$STAGE/本地工作台.app"
cp -R "$APP" "$STAGE/"
ln -sfn /Applications "$STAGE/Applications"
cp packaging/安装说明.txt "$STAGE/安装说明.txt"
hdiutil create -volname '本地工作台' -srcfolder "$STAGE" -ov -format UDZO "releases/LocalWorkbench-$VERSION-macOS-$ARCH.dmg"
shasum -a 256 "releases/LocalWorkbench-$VERSION-macOS-$ARCH.dmg" > releases/SHA256SUMS.txt
