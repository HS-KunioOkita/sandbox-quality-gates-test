#!/usr/bin/env bash
# L2: 依存インストール（手順書 §3.3 ①）
#
# lockfile を絶対とし、インストールスクリプトを無効化する。
# --ignore-scripts のため Prisma Client の生成は走らないので、明示的に生成する。
# Phase 0 の実測では、--ignore-scripts の有無に関わらず pnpm workspace では
# Prisma の postinstall がスキーマを発見できずスタブを生成する。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm

pnpm install --frozen-lockfile --ignore-scripts
raw=$?
if [ "$raw" -ne 0 ]; then
  # lockfile と package.json の不整合（存在しないパッケージの追加など）は fail
  gate_finish "$raw" 1
fi

gate_require_pnpm_tool prisma --version
pnpm --filter api exec prisma generate
gate_finish "$?" 1
