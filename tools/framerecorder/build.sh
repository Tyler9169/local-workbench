#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/框录.app/Contents/{MacOS,Resources} build/AppIcon.iconset
swiftc -target arm64-apple-macosx15.0 -O Sources/main.swift Sources/Geometry.swift ../shared/NativeUpdater.swift -o build/框录.app/Contents/MacOS/FrameRecorder -framework AppKit -framework ScreenCaptureKit -framework AVFoundation -framework Carbon
cp Sources/Info.plist build/框录.app/Contents/Info.plist
swift Sources/Icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/框录.app/Contents/Resources/AppIcon.icns
cp ../shared/install-update.sh build/框录.app/Contents/Resources/
python3 ../shared/sign-app.py build/框录.app
