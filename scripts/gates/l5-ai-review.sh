#!/usr/bin/env bash
# L5: AI レビュー（手順書 §6）
#
# GATE_ORDER にも GATE_DETECTION にも入れない。claude -p は非決定的で、
# 1 回の実行結果を RESULTS.md に恒久的な事実として固定すると誤読を生むため
# （Phase 5 の決定 D1）。反復実測は verification/run-l5.sh が行う。
#
# 手順書 §6.1 は「ブロックさせません」と明記し、§6.3 は `|| true` で
# ビルドを落とさない形を示している。したがって exit code は 0 固定で、
# claude 自体を起動できなかったときだけ 2（error）を返す。
#
# **このゲートは「検出したか」を判定しない。** 何を検出すべきかはケースごとに
# 異なり（L5-02 は N+1、L5-03 は境界値）、ゲート側に持たせるとケース依存の
# 知識がゲートに漏れる。ゲートは生出力をファイルに残すだけにして、判定は
# run-l5.sh に置く。l2-new-deps.sh が marker を出すのとは意図的に異なる。
#
# 出力先は reports/ 配下（.gitignore 済み）。差分の内容——秘密を含みうる——を
# 埋め込むため、追跡ファイルとして残すと次のケースの l2-gitleaks が拾う
# （§1.55 が Stryker のレポートで実測した経路と同型）。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd claude
gate_require_cmd git

BASE_REF="${GATE_BASE_REF:-origin/main}"
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  printf 'gate error: 比較対象の ref が見つかりません: %s\n' "$BASE_REF" >&2
  exit "$GATE_ERROR"
fi

OUT="${L5_REVIEW_OUT:-reports/l5/review.md}"
mkdir -p "${OUT%/*}" || exit 2

# 手順書 §6.3 の逐語は `claude -p "/code-review origin/$_BASE_BRANCH...HEAD"`。
# 比較対象だけを GATE_BASE_REF に置き換える（l2-new-deps.sh と同じ規約。#37(b)）。
claude -p "/code-review $BASE_REF...HEAD" --output-format text >"$OUT" 2>&1
raw=$?

# 手順書 §6.3 の `|| true` に相当する。claude が非ゼロで終わっても
# ブロックしない。ただし何が起きたかは残す。
if [ "$raw" -ne 0 ]; then
  printf 'L5_REVIEW_CLAUDE_EXIT=%s\n' "$raw"
fi

printf 'L5_REVIEW_OUT=%s\n' "$OUT"
exit "$GATE_PASS"
