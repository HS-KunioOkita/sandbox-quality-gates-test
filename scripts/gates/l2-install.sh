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

# pnpm は lockfile 不整合もネットワーク断も同じ 1 を返す。exit code だけを見て
# fail に写像すると、レジストリに繋がらなかっただけの状態が「架空パッケージを
# 検出した」として ✅ 一致になる。ログの理由コードで切り分ける。
_install_log=$(mktemp)
pnpm install --frozen-lockfile --ignore-scripts 2>&1 | tee "$_install_log"
raw="${PIPESTATUS[0]}"
if [ "$raw" -ne 0 ]; then
  # ERR_PNPM_OUTDATED_LOCKFILE : package.json と lockfile がずれている（架空パッケージの追加など）
  # ERR_PNPM_NO_LOCKFILE       : lockfile が無い
  # ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE : 同上の別表現
  gate_fail_if_matches "$_install_log" \
    'ERR_PNPM_OUTDATED_LOCKFILE|ERR_PNPM_NO_LOCKFILE|ERR_PNPM_FROZEN_LOCKFILE'
fi
rm -f "$_install_log"

gate_require_runnable prisma pnpm --filter api exec prisma --version
pnpm --filter api exec prisma generate
gate_finish "$?" 1
