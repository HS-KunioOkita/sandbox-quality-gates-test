#!/usr/bin/env bash
# 1 つの検証ケースを実行する。
#
#   verification/run-case.sh <CASE-ID>
#
# 手順:
#   1. 作業ツリーがクリーンか確認（汚れていたら中断）
#   2. 検証ブランチの残存を確認（あれば中断）
#   3. 現在のブランチから verify/<CASE-ID> ブランチを切る
#   4. case.patch を適用してコミット
#   5. l2-install.sh を先に実行。失敗したら後続を打ち切る
#   6. 残りのゲートを実行し、結果を /tmp に記録
#   7. 元のブランチに戻り検証ブランチを削除。戻れなかったら中断する
#   8. judge.mjs で期待と突き合わせ、TSV 1 行を標準出力へ
#
# 結果を /tmp に書いてから元のブランチに戻るのが要点。検証ブランチ上で
# RESULTS.md を書くとブランチ削除で消える。
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

CASE_ID="${1:-}"
if [ -z "$CASE_ID" ]; then
  printf 'usage: %s <CASE-ID>\n' "$0" >&2
  exit 2
fi

# 作業ツリーの確認は引数の妥当性より先。このスクリプトはブランチを切って
# パッチを当てるので、汚れたツリーでは何もしてはいけない。ケース ID が
# 間違っていても、まず「今この状態では動かせない」を報告する。
if [ -n "$(git status --porcelain)" ]; then
  printf 'エラー: 作業ツリーが汚れています。コミットまたは stash してください\n' >&2
  git status --short >&2
  exit 2
fi

CASE_DIR="verification/cases/$CASE_ID"
if [ ! -f "$CASE_DIR/case.patch" ] || [ ! -f "$CASE_DIR/expect.yml" ]; then
  printf 'エラー: %s に case.patch と expect.yml が必要です\n' "$CASE_DIR" >&2
  exit 2
fi

BRANCH="verify/$CASE_ID"
if git show-ref --quiet "refs/heads/$BRANCH"; then
  printf 'エラー: ブランチ %s が残っています。前回が異常終了しています\n' "$BRANCH" >&2
  printf '  復旧: git branch -D %s\n' "$BRANCH" >&2
  exit 2
fi

BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
# detached HEAD だと BASE_BRANCH が文字列 HEAD になる。すると cleanup の
# `git checkout HEAD` は「今のコミットで detach する」＝欠陥コミットに留まる動作になり、
# branch -D も成功し、事後ガードの HEAD != BASE_BRANCH も HEAD != HEAD で偽になって
# すべてすり抜ける。ユーザーは欠陥コミット上に置き去りにされ、git status はクリーンなので
# 気づけない。入口で弾く。
if [ "$BASE_BRANCH" = "HEAD" ]; then
  printf 'エラー: detached HEAD では実行できません。ブランチをチェックアウトしてください\n' >&2
  exit 2
fi
WORK=$(mktemp -d)
ACTUAL="$WORK/actual.tsv"
LOGS="$WORK/logs"
mkdir -p "$LOGS"

cleanup() {
  git checkout --quiet "$BASE_BRANCH" 2>/dev/null || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 失敗を見逃すと、ユーザーの実ブランチ上で git apply と git commit が行われる。
if ! git checkout --quiet -b "$BRANCH"; then
  printf 'エラー: 検証ブランチ %s を作成できませんでした\n' "$BRANCH" >&2
  exit 2
fi

if ! git apply --index "$CASE_DIR/case.patch" 2>"$LOGS/apply.log"; then
  printf 'エラー: パッチが適用できません。case.patch の更新が必要です\n' >&2
  cat "$LOGS/apply.log" >&2
  exit 2
fi
if ! git commit --quiet -m "verify: $CASE_ID"; then
  printf 'エラー: 検証コミットに失敗しました\n' >&2
  exit 2
fi

# ゲートを実行する。l2-install は必ず先。依存が無ければ他が動かないため、
# また install 失敗による連鎖失敗を「ゲートが欠陥を検出した」と誤記録しないため。
run_gate() {
  local gate="$1"
  local log="$LOGS/$gate.log"
  "./scripts/gates/$gate.sh" >"$log" 2>&1
  local code=$?
  local summary
  summary=$(tail -n 1 "$log" | tr -d '\t' | cut -c1-120)
  printf '%s\t%s\t%s\n' "$gate" "$code" "$summary" >>"$ACTUAL"
  return "$code"
}

if ! run_gate l2-install; then
  printf 'l2-install が pass しなかったため後続ゲートを打ち切りました\n' >&2
else
  run_gate l1-typecheck || true
  run_gate l1-lint || true
fi

cleanup

# cleanup が本当に成功したかを検査する。cleanup 内の git は両方 || true で
# 握り潰しているため、失敗しても何も起きない。ゲートが追跡ファイルを汚すと
# checkout が失敗し、続く branch -D も「チェックアウト中のブランチは消せない」
# ため必ず失敗する。それを見逃すと、欠陥パッチ適用済みの検証ブランチ上で
# judge が走り、正常な JSON を出して exit 0 してしまう。
if [ "$(git rev-parse --abbrev-ref HEAD)" != "$BASE_BRANCH" ] \
  || git show-ref --quiet "refs/heads/$BRANCH"; then
  printf 'エラー: %s への復帰に失敗しました。手動で復旧してください\n' "$BASE_BRANCH" >&2
  printf '  復旧: git checkout -f %s && git branch -D %s\n' "$BASE_BRANCH" "$BRANCH" >&2
  git status --short >&2
  exit 2
fi
trap - EXIT

node verification/lib/judge.mjs "$CASE_DIR/expect.yml" "$ACTUAL"
