#!/bin/sh
# dsh-undo-savepoint 局外 WebUI 启动器（Linux）。需 node >= 20。
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
if ! command -v node >/dev/null 2>&1; then
  echo "[undo] 未找到 Node.js。请先安装 Node.js >= 20。" >&2
  exit 1
fi
exec node "$DIR/undo-server.mjs" "$@"
