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
# turbo はタスク失敗時に 1 を返す。それ以外の非ゼロは turbo 自身の異常なので error。
gate_finish "$?" 1
