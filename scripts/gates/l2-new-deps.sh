#!/usr/bin/env bash
# L2: 新規依存の検出（手順書 §3.3 の末尾）
#
# 非ブロックゲート。手順書は「検出時はラベルを付けて人間レビューへ回す」と書いており、
# ここで CI を落とすことは意図していない。したがって exit code は常に 0 で、
# 判定材料は標準出力の NEW_DEPENDENCY_DETECTED である（設計書 §8.1）。
# 実行そのものができなかった場合だけ 2 を返す。
#
# 手順書は origin/$_BASE_BRANCH を直に埋め込むが、検証ハーネスは feature ブランチから
# verify/<CASE-ID> を切るため、比較対象を GATE_BASE_REF で受け取れるようにする。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd git

BASE_REF="${GATE_BASE_REF:-origin/main}"
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  printf 'gate error: 比較対象の ref が見つかりません: %s\n' "$BASE_REF" >&2
  exit "$GATE_ERROR"
fi

# 手順書 §3.3 の pathspec '**/package.json' は実測でルート直下の package.json に
# 一致しなかった（git のパススペックは既定で ** をシェル glob と同じに扱わないため）。
# '*package.json' はルート直下・apps/* いずれにも一致することを実測済みなのでこちらを使う。
#
# 手順書 §3.3 の grep -E '^\+\s+"' をそのまま使う。これは package.json に追加された
# 引用符で始まる行すべてに一致するので、依存の追加だけでなく scripts の追加や
# 版の変更にも反応する。その粗さ自体が検証対象である。
added=$(git diff "$BASE_REF...HEAD" -- '*package.json' | grep -E '^\+\s+"')
if [ -n "$added" ]; then
  printf '%s\n' "$added"
  printf 'NEW_DEPENDENCY_DETECTED\n'
fi
exit "$GATE_PASS"
