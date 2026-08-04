#!/usr/bin/env bash
# ゲートの一覧と実行順。run-case.sh と run-all.sh の双方がこれを source する。
#
# ここに寄せる理由は、Phase 1 で一覧が run-case.sh と run-all.sh の 2 箇所に
# ハードコードされ、片方だけ更新される事故が起きうる状態だったため（申し送り #18）。
# 対照実行するゲートとケースで実行するゲートがずれると、対照が取れていないまま
# 判定が出る。

# ブロックするゲート。exit code で判定する（0=pass / 1=fail / 2=error）。
# l2-install は必ず先頭に置くこと。依存が入っていなければ他のゲートは動かず、
# 連鎖失敗を「ゲートが欠陥を検出した」と誤記録することになる（設計書 §8.2）。
# shellcheck disable=SC2034  # source する側（gates.test.sh / run-case.sh / run-all.sh）が参照する
GATE_ORDER=(l2-install l1-typecheck l1-lint l2-semgrep l2-osv l2-gitleaks l3-test l3-openapi-drift)

# 非ブロックゲート。exit code は常に 0 なので、出力内容で判定する（設計書 §8.1）。
# shellcheck disable=SC2034  # 同上
GATE_DETECTION=(l2-new-deps)
