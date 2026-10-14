#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/照片置顶.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -target arm64-apple-macosx12.0 Sources/main.swift -o "$APP/Contents/MacOS/PhotoPin" -framework AppKit -framework UniformTypeIdentifiers -O
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PhotoPin</string>
<key>CFBundleIdentifier</key><string>local.tyler.photopin</string>
<key>CFBundleName</key><string>照片置顶</string>
<key>CFBundleDisplayName</key><string>照片置顶</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "已生成：$APP"
