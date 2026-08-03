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

# Jest はテスト失敗もコンテナ起動失敗も 1 を返す。ログに「テストが実際に走って
# 失敗した」証跡があるときだけ fail に写像し、それ以外は error に倒す。
#
# 判定に使う文字列:
#   'Tests:.*failed'   Jest のサマリ行（例: `Tests: 1 failed, 3 passed, 4 total`）
#   'Test suites?:.*failed'  スイート単位の失敗（テストが 1 件も走らずスイートが落ちた場合も含む）
# のうち前者だけを fail とする。後者だけが出ている場合は、テストファイルの
# import が解決できない・コンテナが起動しないといった「走れなかった」側の可能性が
# 高いため error に残す。
gate_fail_if_matches "$_test_log" 'Tests:.*[0-9]+ failed'
