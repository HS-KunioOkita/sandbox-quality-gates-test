#!/usr/bin/env bash
# ゲートスクリプトの exit code 契約を検証する。
# 0 = pass / 1 = fail / 2 = error
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit
# shellcheck source=scripts/gates/gates.list.sh
source scripts/gates/gates.list.sh

FAILURES=0
TOTAL=0

check() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    printf 'ok   %s (exit %s)\n' "$label" "$actual"
  else
    printf 'FAIL %s: expected exit %s, got %s\n' "$label" "$expected" "$actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- クリーンなツリーでは全ブロックゲートが pass ---
for gate in "${GATE_ORDER[@]}"; do
  "./scripts/gates/$gate.sh" >/dev/null 2>&1
  check "$gate はクリーンなツリーで pass" 0 "$?"
done

# --- 非ブロックゲートは検出が無ければ pass かつ無出力 ---
out=$(GATE_BASE_REF=HEAD ./scripts/gates/l2-new-deps.sh 2>/dev/null)
check 'l2-new-deps は差分が無いとき pass' 0 "$?"
case "$out" in
  *NEW_DEPENDENCY_DETECTED*) check 'l2-new-deps は差分が無いとき検出しない' 'no-marker' 'marker' ;;
  *) check 'l2-new-deps は差分が無いとき検出しない' 'no-marker' 'no-marker' ;;
esac

# --- 必要なコマンドが無いときは error(2) ---
# PATH から pnpm と docker を外す。どちらも volta / homebrew などルート外に入るので
# /usr/bin:/bin に絞れば消える。一方 env と bash はここに居るので、
# スクリプト自体は起動できてガードまで到達する。
# PATH=/nonexistent は使えない。`#!/usr/bin/env bash` の bash 解決ごと壊れ、
# ゲートが起動する前にシェルが 127 で落ちるため、ゲートの正規化を検証できない。
for gate in "${GATE_ORDER[@]}"; do
  ( PATH=/usr/bin:/bin "./scripts/gates/$gate.sh" ) >/dev/null 2>&1
  check "$gate はツールが無いとき error" 2 "$?"
done

# --- Docker ゲートはデーモンに到達できないとき error(2) ---
# PATH を絞る上のテストでは docker バイナリ自体が消えるので gate_require_cmd で止まり、
# gate_require_docker の本体である docker info の分岐に到達しない。設計書 §6.1 が
# 「このハーネス最大の誤判定リスク」と呼ぶのはデーモン不在の方なので、そこを直接突く。
# DOCKER_HOST を存在しないソケットに向ければ、バイナリは在るまま到達不能を作れる
# （Docker Desktop を止める必要はない。Task 2 で実測）。
for gate in l2-semgrep l2-osv l2-gitleaks l3-test; do
  out=$( DOCKER_HOST=unix:///nonexistent/docker.sock "./scripts/gates/$gate.sh" 2>&1 )
  code=$?
  check "$gate はデーモンに到達できないとき error" 2 "$code"
  # exit code だけでは 2 つのガードを区別できない。メッセージで到達点を確かめる。
  case "$out" in
    *'Docker デーモンが起動していません'*)
      check "$gate は docker info の分岐に到達する" 'daemon-msg' 'daemon-msg' ;;
    *)
      check "$gate は docker info の分岐に到達する" 'daemon-msg' 'other-msg' ;;
  esac
done

# --- 非ブロックゲートは比較対象が無いとき error(2) ---
( GATE_BASE_REF=no-such-ref ./scripts/gates/l2-new-deps.sh ) >/dev/null 2>&1
check 'l2-new-deps は比較対象が無いとき error' 2 "$?"

# --- どのカレントディレクトリからでも動く ---
# ゲートは自分でリポジトリルートへ移動するので、呼び出し位置に依存しない。
# ハーネスと CI がこれに依存する。
GATE_ABS="$PWD/scripts/gates"
for gate in "${GATE_ORDER[@]}"; do
  ( cd / && "$GATE_ABS/$gate.sh" ) >/dev/null 2>&1
  check "$gate は / から呼んでも pass" 0 "$?"
done

# --- L5（非ブロック・GATE_ORDER 外）の error 経路 ---
# l5-ai-review は exit code で欠陥を主張しない（常に 0）。したがって
# 「動かなかったのに緑」を防げるのは error(2) のガードだけである。そこを直接突く。
GATE_BASE_REF=refs/heads/does-not-exist ./scripts/gates/l5-ai-review.sh >/dev/null 2>&1
check 'l5-ai-review は比較対象が無いとき error' 2 "$?"

env -i PATH=/usr/bin:/bin HOME="$HOME" bash ./scripts/gates/l5-ai-review.sh >/dev/null 2>&1
check 'l5-ai-review は claude が無いとき error' 2 "$?"

# --- L4 が実際に Stryker を起動できることを確認する（申し送り #41） ---
# run-all.sh の baseline も既存のテストも、apps/api/src に差分が無い状態でしか
# stryker-diff.sh を呼んでいない。どちらも L4_MUTATE_FILES=(none) のスキップ経路で
# 緑になるため、**このリポジトリの自動チェックのどれ一つも「Stryker が実際に
# 起動できる」ことを確認していなかった**。ここで初めてその経路を通す。
#
# 一時ブランチを切って無害な差分を 1 つ作り、元ブランチを GATE_BASE_REF に渡す。
# run-case.sh（verification/run-case.sh:58-73, 79-83, 212-218）と同じ 3 つの防御を
# 持たせる。無くても「下流のコマンドが非ゼロで返る」失敗では -e が無いこの
# スクリプトはブロック末尾まで到達して後始末できるが、それとは別の 2 つの
# 失敗クラス——(1) 前回の異常終了でブランチが残っている場合の checkout -b 自体の
# 失敗、(2) Stryker 実行中の割り込み（Ctrl-C 等）——は末尾の後始末に到達する前に
# 状態を壊す。前者は実ブランチへの意図しないコミットを、後者は Stryker の
# mutation レポート（ミューテート対象のソース全文を埋め込む。§1.55 と同型の
# 汚染経路）の残留を招く。
#   1. 入口で残存ブランチと detached HEAD を検出する（run-case.sh:58-73 と同型）。
#   2. trap で割り込み時も後始末する（run-case.sh:79-83 と同型）。
#   3. 後始末の後、実際に元ブランチへ戻れたか・一時ブランチが消えたかを検査する
#      （run-case.sh:212-218 と同型）。cleanup 内の git は || true で握り潰して
#      いるため、失敗しても何も起きない。
# 残るリスク: SIGKILL のように trap 自体が発火しない終了はここでも防げない。
# その場合の手動復旧は次の cleanup 関数と同じ内容
# （git checkout -f <元ブランチ> && git branch -D tmp/gates-test-l4 &&
#   rm -rf apps/api/reports/mutation）。
_l4_selftest() {
  local base
  base=$(git rev-parse --abbrev-ref HEAD)
  if [ "$base" = "HEAD" ]; then
    printf 'stryker-diff の実起動チェック: detached HEAD では実行できません\n' >&2
    return 2
  fi
  if git show-ref --quiet refs/heads/tmp/gates-test-l4; then
    printf 'stryker-diff の実起動チェック: ブランチ tmp/gates-test-l4 が残っています。前回が異常終了しています\n' >&2
    printf '  復旧: git branch -D tmp/gates-test-l4\n' >&2
    return 2
  fi

  _l4_cleanup() {
    git checkout --quiet "$base" 2>/dev/null || true
    git branch -D tmp/gates-test-l4 >/dev/null 2>&1 || true
    rm -rf apps/api/reports/mutation
  }
  trap _l4_cleanup EXIT

  if ! git checkout --quiet -b tmp/gates-test-l4; then
    printf 'stryker-diff の実起動チェック: 一時ブランチを作成できませんでした\n' >&2
    _l4_cleanup
    trap - EXIT
    return 2
  fi

  printf '\n// gates.test.sh が Stryker の実起動を確認するための一時的な差分\n' >> apps/api/src/discount/discount.ts
  # -a ではなく対象ファイルを明示する。-a は追跡中の全変更をステージするため、
  # gates.test.sh 自身の未コミット編集など無関係な変更まで一時ブランチのコミットに
  # 混入し、後段の branch -D で失われる（実測で発生）。
  git commit --quiet -m "tmp: gates.test.sh の L4 実起動確認" -- apps/api/src/discount/discount.ts

  GATE_BASE_REF="$base" ./scripts/stryker-diff.sh >/tmp/gates-test-l4.log 2>&1
  check 'stryker-diff は差分があるとき Stryker を起動して pass' 0 "$?"
  grep -qE 'L4_MUTATE_FILES=src/discount/discount\.ts' /tmp/gates-test-l4.log
  check 'stryker-diff はミューテート対象を出力する' 0 "$?"
  grep -qE 'Mutation score|mutant\(s\)' /tmp/gates-test-l4.log
  check 'stryker-diff は実際に mutant を実行する' 0 "$?"

  _l4_cleanup
  trap - EXIT

  if [ "$(git rev-parse --abbrev-ref HEAD)" != "$base" ] || git show-ref --quiet refs/heads/tmp/gates-test-l4; then
    printf 'stryker-diff の実起動チェック: %s への復帰に失敗しました。手動で復旧してください\n' "$base" >&2
    printf '  復旧: git checkout -f %s && git branch -D tmp/gates-test-l4\n' "$base" >&2
    return 1
  fi
  return 0
}

_l4_selftest
check 'stryker-diff の実起動チェックが安全に完走する（前提確認と後始末を含む）' 0 "$?"

if [ "$FAILURES" -eq 0 ]; then
  printf '\n全 %s 件のチェックが成功しました\n' "$TOTAL"
  exit 0
fi
printf '\n%s / %s 件のチェックが失敗しました\n' "$FAILURES" "$TOTAL"
exit 1
