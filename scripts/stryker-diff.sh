#!/usr/bin/env bash
# 手順書 §5.3 の差分限定ミューテーション実行。
#
# 手順書の原文からの変更点は 4 つ。すべて「手順書どおりでは何も測れない」ことを
# 実測してから入れた（詳細は docs/superpowers/phase0-findings.md §1.45 以降）。
#
#   1. --mutate に渡すパスをパッケージ相対に直す（仮説 4）。git diff はリポジトリ
#      ルート相対（apps/api/src/...）を返すが、pnpm --filter api exec は apps/api を
#      カレントにするので、そのまま渡すと apps/api/apps/api/src/... を探して空振りする。
#   2. pathspec を 'apps/api/src' にする。'apps/api/src/**/*.ts' は git の pathspec
#      では src 直下のファイルに一致しない（§1.23 と同型）。
#   3. git fetch を廃し、比較対象を GATE_BASE_REF で受け取る。検証ハーネスは main から
#      切ったローカルの検証ブランチ上で走るので origin への fetch は不要で、
#      ネットワーク障害をゲートの失敗に化けさせるだけである（l2-new-deps.sh と同じ方針）。
#   4. ミューテート対象のファイル名を必ず標準出力に出す。差分 0 件でスキップした緑と
#      「実際にミューテートして生き残らなかった」緑を、ログから区別できるようにする
#      （§1.43 の「何が走ったか分からない緑」を作らないため）。
set -euo pipefail

BASE_REF="${GATE_BASE_REF:-origin/${BASE_BRANCH:-main}}"
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  printf 'stryker-diff: 比較対象の ref が見つかりません: %s\n' "$BASE_REF" >&2
  exit 3
fi

CHANGED=$(git diff --name-only "$BASE_REF...HEAD" -- 'apps/api/src' \
  | grep -E '\.ts$' | grep -v '\.spec\.ts$' || true)

if [ -z "$CHANGED" ]; then
  printf 'L4_MUTATE_FILES=(none)\n'
  echo "変更なし。スキップします。"
  exit 0
fi

MUTATE=$(printf '%s\n' "$CHANGED" | sed 's|^apps/api/||' | paste -sd, -)
printf 'L4_MUTATE_FILES=%s\n' "$MUTATE"
pnpm --filter api exec stryker run --mutate "$MUTATE"
