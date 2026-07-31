#!/usr/bin/env bash
# L2: シークレット混入チェック（手順書 §3.3 ③）
#
# 手順書は `gitleaks detect --no-git --redact` と書く。gitleaks 8.30.1 では `detect` は
# `gitleaks --help` に載らない非推奨サブコマンドで、現行は `gitleaks dir [flags] [path]` だが、
# 手順書のコマンドをそのまま検証するのが目的なので detect を使う。
#
# なお `dir` に `--no-git` を渡すと exit 126（unknown flag）になる。126 は fail に
# 写像してはいけない。書式ミスを「秘密を検出した」と読み違えることになる。
#
# --config を明示するのは、.gitleaks.toml の自動検出が効かないため（実測）。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_docker

docker run --rm -v "$PWD:/src:ro" "$GATE_IMG_GITLEAKS" \
  detect --no-git --redact --source=/src --config /src/.gitleaks.toml
# gitleaks は漏洩を見つけると 1 を返す。書式ミスは 126、その他の異常も非ゼロなので
# error 側に残す。
gate_finish "$?" 1
