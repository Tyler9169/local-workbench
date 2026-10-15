#!/bin/zsh
cd "${0:A:h}"
NODE=$(command -v node)
if [[ -z "$NODE" && -x "$HOME/.local/node-v24.21.0-darwin-arm64/bin/node" ]]; then
  NODE="$HOME/.local/node-v24.21.0-darwin-arm64/bin/node"
fi
if [[ -z "$NODE" ]]; then
  echo "需要 Node.js 22 或以上版本才能启动。"
  read -k 1
  exit 1
fi
if [[ ! -x "node_modules/electron/dist/Electron.app/Contents/MacOS/Electron" ]]; then
  echo "桌面组件尚未就绪。请在本目录运行 npm install，再运行 node node_modules/electron/install.js。"
  echo "网页计时仍可使用；安装后即可开启桌面悬浮。"
fi
"$NODE" server.mjs
