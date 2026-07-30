#!/usr/bin/env bash
# L2: SAST（手順書 §3.2）
#
# 手順書は `semgrep ci ... --error` と書くが、実測では動かない:
#   - `semgrep ci` は --error を受け付けない（exit 2 / unknown option）
#   - `semgrep ci` は --config 無し・未ログインだと何もせず exit 0 を返す
# 後者が危険である。ゲートが緑なのに何も見ていない状態になる。
# 設計書 §6 の読み替え（semgrep ci → semgrep scan）に従う。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_docker

docker run --rm -v "$PWD:/src:ro" -w /src "$GATE_IMG_SEMGREP" semgrep scan \
  --config p/typescript \
  --config p/nodejs \
  --config p/react \
  --config p/owasp-top-ten \
  --config p/secrets \
  --config .semgrep/ \
  --error
# semgrep は findings で 1、設定エラー・CLI 誤り・レジストリ到達不能で 2 を返す。
# 2 を fail に写像すると「ルールを取ってこられなかった」が「脆弱性を検出した」になる。
gate_finish "$?" 1
