#!/usr/bin/env bash
# L1: 型チェック（手順書 §2.5）
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm

pnpm turbo typecheck
# turbo は子プロセスの exit code をそのまま透過する。tsc は型エラーで 2 を返すので
# fail は 2 である。turbo 自身の異常（タスク名が無い / turbo.json が壊れている）は 1 なので、
# 1 は error 側に残す。ここを `gate_finish "$?" 1` にすると型エラーが「ツールが実行できなかった」
# と記録され、逆に turbo の設定ミスが「欠陥を検出した」になる。実測で確認済み:
#   型エラーあり → 2 / 存在しないタスク名 → 1 / 壊れた turbo.json → 1
gate_finish "$?" 2
