#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p releases
package() {
  local name="$1" source="$2" file="$3" minimum="$4"
  local stage="build/package-$file"
  mkdir -p "$stage"
  ditto "$source" "$stage/$name.app"
  ln -sfn /Applications "$stage/Applications"
  printf '%s\n\n适用：Apple Silicon Mac，macOS %s 或更新版本。\n将应用拖入 Applications 后打开。\n未经 Apple 开发者签名与公证；首次打开可能需要你在系统设置中允许。\n框录需要屏幕录制权限，开启麦克风时还需要麦克风权限。\n请从 Tyler9169/local-workbench 的 GitHub Releases 获取安装包。\n' "$name" "$minimum" > "$stage/安装说明.txt"
  /usr/bin/ditto -c -k --norsrc --keepParent "$source" "releases/$file.zip"
  codesign --verify --deep --strict "$stage/$name.app"
  hdiutil create -volname "$name" -srcfolder "$stage" -ov -format UDZO "releases/$file.dmg"
}
package '照片置顶' 'tools/photopin/照片置顶.app' 'PhotoPin-1.1.0-macOS-arm64' '12'
package '框录' 'tools/framerecorder/build/框录.app' 'FrameRecorder-1.2.0-macOS-arm64' '15'
(cd releases && shasum -a 256 *.dmg > SHA256SUMS.txt)
