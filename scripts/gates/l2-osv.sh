#!/usr/bin/env bash
# L2: 依存ライブラリの既知脆弱性スキャン（手順書 §3.3 ②）
#
# 手順書は `osv-scanner --lockfile=pnpm-lock.yaml` と書く。これは v1 の書式だが、
# 実測では v2.4.0 も受け付ける（設計書 §6 の「v1/v2 で CLI 書式が異なる」への回答）。
# 手順書のコマンドをそのまま検証するのが目的なので、v2 の `scan source -L` ではなく
# 手順書どおりの書式を使う。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_docker

docker run --rm -v "$PWD:/src:ro" -w /src "$GATE_IMG_OSV" --lockfile=pnpm-lock.yaml
# osv-scanner は脆弱性を見つけると 1 を返す（実測: クリーン時の 0 と脆弱性検出時の 1
# のみ実測済み）。それ以外の非ゼロは error に落とす。lockfile 不在・ネットワーク断・
# イメージ起動失敗が実際にどの非ゼロ値を返すかは未実測であり、ここは「1 以外は
# error であるべき」という設計方針であって実測に基づく記述ではない。
gate_finish "$?" 1
