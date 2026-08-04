#!/usr/bin/env bash
# L4: ミューテーションテスト（手順書 §5）
#
# 手順書 §7 の cloudbuild は L4 のステップを `./scripts/stryker-diff.sh` の呼び出し
# だけで書いている。ここもそれに合わせ、差分限定の実行を薄く包んで exit code を
# 3 値へ正規化するだけにする。
#
# Docker は要らない。Stryker が回すのは Jest の unit プロジェクトだけで
# （apps/api/jest.stryker.config.ts）、Testcontainers を使う integration / e2e は
# 含まないため（申し送り #28）。gate_require_docker を呼ばないのは意図的である。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm
# ガード対象と同じスコープで呼ぶ（§1.12）。pnpm のフィルタは exec より前に置く必要がある。
gate_require_runnable 'stryker' pnpm --filter api exec stryker --version

_log=$(mktemp)
./scripts/stryker-diff.sh 2>&1 | tee "$_log"
raw="${PIPESTATUS[0]}"

if [ "$raw" -eq 0 ]; then
  rm -f "$_log"
  exit "$GATE_PASS"
fi

# Stryker は「閾値割れ」も「初回テスト実行の失敗」も「設定エラー」も同じ 1 を返す。
# 閾値割れのときだけログに出る文字列で切り分ける。初回テスト実行の失敗を fail に
# 写像すると、「テストが落ちている」が「ミューテーションテストが空虚なテストを
# 検出した」になる（§1.44 と同じ型の事故）。
#
# 実測（Task 4）:
#   閾値割れ:         `ERROR MutationTestReportHelper[39m Final mutation score 26.23 under breaking threshold 50, setting exit code to 1 (failure).`
#   初回テスト失敗:     `ERROR Stryker[39m There were failed tests in the initial test run.`
#   対象に関連テストが 0 件（dry run 自体が空）: `ERROR Stryker[39m No tests were executed. Stryker will exit prematurely. Please check your configuration.`
# 後 2 つはいずれも ConfigError で、"Final mutation score" という文字列を出さない。
# 'Final mutation score .* under breaking threshold' は閾値割れのときにしか
# 現れないため、この 2 つのログには一致せず error(2) に落ちる（実測で確認済み）。
#
# stryker-diff.sh が返す 3（比較対象の ref が無い）はこのパターンに一致しないので
# error(2) に落ちる。これは意図した写像である。
gate_fail_if_matches "$_log" 'Final mutation score .* under breaking threshold'
