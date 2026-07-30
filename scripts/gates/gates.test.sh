#!/usr/bin/env bash
# ゲートスクリプトの exit code 契約を検証する。
# 0 = pass / 1 = fail / 2 = error
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

FAILURES=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'ok   %s (exit %s)\n' "$label" "$actual"
  else
    printf 'FAIL %s: expected exit %s, got %s\n' "$label" "$expected" "$actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- クリーンなツリーでは全ゲートが pass ---
./scripts/gates/l1-typecheck.sh >/dev/null 2>&1
check 'l1-typecheck はクリーンなツリーで pass' 0 "$?"

./scripts/gates/l1-lint.sh >/dev/null 2>&1
check 'l1-lint はクリーンなツリーで pass' 0 "$?"

# --- 必要なコマンドが無いときは error(2) ---
# PATH から pnpm を外す。pnpm は volta / homebrew などルート外に入るので
# /usr/bin:/bin に絞れば消える。一方 env と bash はここに居るので、
# スクリプト自体は起動できて gate_require_cmd まで到達する。
# PATH=/nonexistent は使えない。`#!/usr/bin/env bash` の bash 解決ごと壊れ、
# ゲートが起動する前にシェルが 127 で落ちるため、ゲートの正規化を検証できない。
( PATH=/usr/bin:/bin ./scripts/gates/l1-lint.sh ) >/dev/null 2>&1
check 'l1-lint は pnpm が無いとき error' 2 "$?"

( PATH=/usr/bin:/bin ./scripts/gates/l1-typecheck.sh ) >/dev/null 2>&1
check 'l1-typecheck は pnpm が無いとき error' 2 "$?"

# --- どのカレントディレクトリからでも動く ---
# ゲートは自分でリポジトリルートへ移動するので、呼び出し位置に依存しない。
# ハーネスと CI がこれに依存する。
GATE_ABS="$PWD/scripts/gates"
( cd / && "$GATE_ABS/l1-lint.sh" ) >/dev/null 2>&1
check 'l1-lint は / から呼んでも pass' 0 "$?"

( cd / && "$GATE_ABS/l1-typecheck.sh" ) >/dev/null 2>&1
check 'l1-typecheck は / から呼んでも pass' 0 "$?"

TOTAL=6
if [ "$FAILURES" -eq 0 ]; then
  printf '\n全 %s 件のチェックが成功しました\n' "$TOTAL"
  exit 0
fi
printf '\n%s / %s 件のチェックが失敗しました\n' "$FAILURES" "$TOTAL"
exit 1
