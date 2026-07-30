#!/usr/bin/env bash
# L1: Lint（手順書 §2.5）
#
# --max-warnings=0 が要点。warn は CI では実質無視され溜まる一方になるため、
# ゲートにするなら警告ゼロを強制する（手順書 §2.5）。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm
gate_require_runnable eslint pnpm exec eslint --version

pnpm exec eslint . --max-warnings=0
# ESLint: 1 = lint エラーまたは警告数超過（fail）、2 = 設定エラー（error）
gate_finish "$?" 1
