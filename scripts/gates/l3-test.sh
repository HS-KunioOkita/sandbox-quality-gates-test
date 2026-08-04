#!/usr/bin/env bash
# L3: テスト（手順書 §4.6）
#
# 手順書は `pnpm turbo test --filter='...[origin/main]'` と書くが、ここでは
# フィルタを外して全パッケージを走らせる。検証ハーネスは main から切った
# 検証ブランチ上で実行するので、`...[origin/main]` は「origin/main からの差分」を
# 見る。origin にまだ無いコミットとの比較になり、ケースによって走る範囲が
# 変わってしまう。何が走ったか分からないゲートでは判定に使えない。
# この差自体は手順書への注記候補として findings に残す。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm
# 統合テストと e2e は Testcontainers で PostgreSQL を立てる。Docker が無い状態で
# 走らせると Jest はテスト失敗（exit 1）として報告する。それを fail に写像すると
# 「Docker Desktop が止まっている」が「テストが欠陥を検出した」になる。
# ここで先に error(2) へ倒す。
gate_require_docker

# turbo 経由で実行する。turbo.json の test は dependsOn に generate を持つので、
# Prisma Client の生成が先行する。直叩き（pnpm --filter api exec jest）では
# 生成が走らない（申し送り #13 と同じ型）。
_test_log=$(mktemp)
pnpm turbo test 2>&1 | tee "$_test_log"
raw="${PIPESTATUS[0]}"

if [ "$raw" -eq 0 ]; then
  rm -f "$_test_log"
  exit "$GATE_PASS"
fi

# Jest も Vitest もテスト失敗もコンテナ起動失敗も 1 を返す。ログに「テストが実際に
# 走って失敗した」証跡があるときだけ fail に写像し、それ以外は error に倒す。
#
# 判定に使うのはテスト件数のサマリ行だけである。このゲートはフィルタ無しで
# `pnpm turbo test` を走らせるので api（Jest）と web（Vitest）の両方が対象に入り、
# **同じモノレポで 2 つのテストランナーがそれぞれ違う書式のサマリを出す**（実測）:
#   Jest   `Tests:       1 failed, 27 passed, 28 total`  コロンあり・カンマ区切り
#   Vitest `      Tests  1 failed | 10 passed (11)`      コロン無し・パイプ区切り
# さらに turbo 経由の Vitest は `Tests` と件数の間に ANSI の色付けエスケープを
# 挟む（実測。cat -v 表記で `Tests ^[[22m ^[[1m^[[31m2 failed`）ため、空白文字
# だけを許すパターンでは一致しない。ここは `.*` で両方の書式を吸収する。
#
# スイート単位の見出し（Jest の `Test Suites:` / Vitest の `Test Files`）は判定に
# 使わない。どちらも文字列 `Tests` を含まないので下のパターンには一致しない。
# テストが 1 件も走らずスイートだけが落ちた場合は、テストファイルの import が
# 解決できない・コンテナが起動しないといった「走れなかった」側の可能性が高いため
# error に残す（§1.36 で実際にこの形の exit 2 を観測している）。
gate_fail_if_matches "$_test_log" 'Tests.*[0-9]+ failed'
