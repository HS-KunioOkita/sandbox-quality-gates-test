#!/usr/bin/env bash
# L3: Web の E2E（手順書 §4.1「△ 主要導線のみ」）
#
# GATE_ORDER には入れない。手順書 §4.1 と付録は Playwright を「主要導線のみ PR、
# フルは nightly」と位置づけており、全検証ケースで Postgres + API + Vite +
# ブラウザを起こすと run-all.sh の所要時間が跳ねるため、Phase 5 の nightly 検証で
# 実行する。実行手段だけをここに用意しておく。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm
gate_require_docker
gate_require_runnable playwright pnpm --filter web exec playwright --version

_log=$(mktemp)
pnpm --filter web exec playwright test 2>&1 | tee "$_log"
raw="${PIPESTATUS[0]}"

if [ "$raw" -eq 0 ]; then
  rm -f "$_log"
  exit "$GATE_PASS"
fi

# playwright はテスト失敗もサーバ起動失敗も 1 を返す。l3-test と同じ理由で
# ログの証跡を見る。'N failed' はテストが実際に走って落ちたときだけ出る。
gate_fail_if_matches "$_log" '[0-9]+ failed'
