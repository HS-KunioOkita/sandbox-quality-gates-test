#!/usr/bin/env bash
# ゲートスクリプト共通のヘルパ。
#
# exit code の契約:
#   0 = pass  ゲート通過
#   1 = fail  ゲートがブロックした（＝欠陥を検出した）
#   2 = error ツールが実行できなかった（判定不能）
#
# 各ツールの生 exit code は多様なので（Semgrep は 1=findings/2=error、
# ESLint は 1=lint error/2=config error など）、この 3 値へ明示的に写像する。
# error を fail と誤って記録すると「Docker が起動していないだけ」を
# 「欠陥を検出した」と読み違えるため、区別が最重要である。

GATE_PASS=0
GATE_FAIL=1
GATE_ERROR=2

# 指定コマンドが使えなければ error で終了する
gate_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'gate error: コマンドが見つかりません: %s\n' "$cmd" >&2
    exit "$GATE_ERROR"
  fi
}

# git リポジトリの中にいることを確認する。移動はしない（呼び出し側が済ませている）。
gate_require_repo() {
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    printf 'gate error: git リポジトリの中で実行してください（現在: %s）\n' "$PWD" >&2
    exit "$GATE_ERROR"
  fi
}

# 生 exit code を 3 値へ正規化して終了する。
#   $1        生 exit code
#   $2 以降   fail とみなす生 exit code（列挙）
# 列挙に無い非ゼロは error とみなす。
gate_finish() {
  local raw="$1"
  shift
  if [ "$raw" -eq 0 ]; then
    exit "$GATE_PASS"
  fi
  local code
  for code in "$@"; do
    if [ "$raw" -eq "$code" ]; then
      exit "$GATE_FAIL"
    fi
  done
  printf 'gate error: 予期しない exit code: %s\n' "$raw" >&2
  exit "$GATE_ERROR"
}
