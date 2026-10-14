#!/bin/bash
# Called with positional arguments only; no eval, sudo, TCC changes, or preference deletion.
set -euo pipefail
parent="$1"; target="$2"; stage="$3"; support="$4"; token="$5"
backup="${target}.backup-${token}"
lock="${target}.update-lock"
ack="$support/$token.ready"
error="$support/last-error.txt"
new="$stage/Application.app"
log_error() { printf '%s\n' "$1" > "$error"; }
if ! mkdir "$lock"; then log_error '另一个更新正在安装，请稍后重试。'; exit 1; fi
cleanup() { rmdir "$lock" 2>/dev/null || true; }
trap cleanup EXIT
for ((i=0;i<30;i++)); do
  if ! kill -0 "$parent" 2>/dev/null; then break; fi
  sleep 1
done
if kill -0 "$parent" 2>/dev/null; then log_error '应用未能退出；原版本未被修改。请退出后重试。'; exit 1; fi
if [[ ! -d "$target" || ! -d "$new" ]]; then log_error '更新文件不存在；原版本未被修改。'; exit 1; fi
/usr/bin/codesign --verify --deep --strict "$new"
mv "$target" "$backup"
if ! mv "$new" "$target"; then
  mv "$backup" "$target"; log_error '替换失败，已恢复原版本。'; /usr/bin/open -n "$target"; exit 1
fi
if /usr/bin/open -n "$target" --args --native-update-token "$token"; then
  for ((i=0;i<60;i++)); do
    if [[ -f "$ack" ]]; then
      printf '%s\n' "$backup" > "$support/last-backup.txt"
      rm -f "$ack" "$error"
      rmdir "$stage" 2>/dev/null || true
      exit 0
    fi
    sleep 1
  done
fi
# Retain the failed bundle for diagnosis. Never touch the user's preference domain or files.
mv "$target" "$stage/Failed.app"
mv "$backup" "$target"
log_error '新版未能完成启动，已恢复原版本。若新版窗口仍在，请关闭它后重新打开应用。'
/usr/bin/open -n "$target"
exit 1
