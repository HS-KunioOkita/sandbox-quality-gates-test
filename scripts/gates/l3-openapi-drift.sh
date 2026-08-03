#!/usr/bin/env bash
# L3: OpenAPI 生成物の drift 検出（手順書 §4.4 ③）
#
# API 側の DTO を変えたのに Web 側の生成型を更新していない状態を検出する。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm

SCHEMA=apps/web/src/api/schema.d.ts

# このゲートは追跡ファイル（schema.d.ts）を書き換える。検証ハーネスは検証ブランチから
# 元ブランチへ git checkout で戻るので、汚れたまま終わるとその checkout が失敗し、
# ケース全体が exit 2 になる（run-case.sh の復帰ガード）。どの経路で終わっても
# 必ず戻す。手順書 §4.4 はゲートが作業ツリーを汚す点に触れていない。
# shellcheck disable=SC2329  # trap 経由でのみ呼ばれるため呼び出し箇所を静的に追えない（偽陽性）
restore_schema() {
  git checkout --quiet -- "$SCHEMA" 2>/dev/null || true
}
trap restore_schema EXIT

_log=$(mktemp)
if ! pnpm --filter api run generate:openapi >"$_log" 2>&1; then
  printf 'gate error: OpenAPI の生成に失敗しました\n' >&2
  cat "$_log" >&2
  rm -f "$_log"
  exit "$GATE_ERROR"
fi

if ! pnpm --filter web exec openapi-typescript ../../openapi.json -o src/api/schema.d.ts >>"$_log" 2>&1; then
  printf 'gate error: 型の生成に失敗しました\n' >&2
  cat "$_log" >&2
  rm -f "$_log"
  exit "$GATE_ERROR"
fi
rm -f "$_log"

# 手順書 §4.4 ③ のコマンド。差分があれば 1、無ければ 0。
# git diff の非ゼロは 1 だけを fail とし、他（128 = リポジトリ外など）は error に倒す。
git diff --exit-code "$SCHEMA"
gate_finish "$?" 1
