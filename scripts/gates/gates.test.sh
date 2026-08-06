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
# l5-ai-review は exit code で欠陥を主張しない(常に 0)。したがって
# 「動かなかったのに緑」を防げるのは error(2) のガードだけである。そこを直接突く。
GATE_BASE_REF=refs/heads/does-not-exist ./scripts/gates/l5-ai-review.sh >/dev/null 2>&1
check 'l5-ai-review は比較対象が無いとき error' 2 "$?"

env -i PATH=/usr/bin:/bin HOME="$HOME" bash ./scripts/gates/l5-ai-review.sh >/dev/null 2>&1
check 'l5-ai-review は claude が無いとき error' 2 "$?"

if [ "$FAILURES" -eq 0 ]; then
  printf '\n全 %s 件のチェックが成功しました\n' "$TOTAL"
  exit 0
fi
printf '\n%s / %s 件のチェックが失敗しました\n' "$FAILURES" "$TOTAL"
exit 1
