#!/bin/bash
# 同步 workspace skill 源 → SPM 资源目录（App Bundle 内置 skill 的唯一来源，Story-1031-mcp）
# 用法：scripts/sync-skill.sh [--check]
#   默认：镜像 skills/git-space 到 Packages/GSMCP/Sources/GSMCP/Skill
#   --check：只校验两侧一致，不一致时退出码 1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/../../skills/git-space"
DST="$ROOT/Packages/GSMCP/Sources/GSMCP/Skill"

[ -d "$SRC" ] || { echo "错误：skill 源不存在：$SRC"; exit 1; }

if [ "${1:-}" = "--check" ]; then
  if diff -r "$SRC" "$DST" >/dev/null 2>&1; then
    echo "一致：skill 源与 Bundle 资源一致"
    exit 0
  fi
  echo "不一致：请先运行 scripts/sync-skill.sh"
  diff -rq "$SRC" "$DST" || true
  exit 1
fi

mkdir -p "$DST"
rsync -a --delete --exclude '.DS_Store' "$SRC/" "$DST/"
echo "已同步：$SRC → $DST"
diff -r "$SRC" "$DST" >/dev/null
echo "校验通过"
