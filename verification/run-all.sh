#!/usr/bin/env bash
# 全検証ケースを実行し verification/RESULTS.md を生成する。
set -uo pipefail

# git rev-parse --show-toplevel はリポジトリ外だと exit 128 で標準出力が空になる。
# ここで `cd "$(...)" || exit 2` の形にしても意味がない。**`cd ""` は bash では
# exit 0 を返す**（実測。ディレクトリは変わらないが失敗として扱われない）ため、
# コマンド置換の終了ステータスと空文字列を別々に検査する必要がある。
# 見逃すと -e を付けていないためスクリプトはそのまま続行し、以降の処理が
# 無関係なディレクトリで走る事故になりうる（SC2164）。ここで exit 2（error）
# にする。これは「ハーネスが実行できなかった」状態であり、ゲートの pass/fail
# の判定に使ってはいけないため 0/1 ではなく 2 にする。
toplevel=$(git rev-parse --show-toplevel) || exit 2
[ -n "$toplevel" ] || exit 2
cd "$toplevel" || exit 2

# shellcheck source=scripts/gates/gates.list.sh
source scripts/gates/gates.list.sh

RESULTS=verification/RESULTS.md
WORK=$(mktemp -d)

# 対照実行。パッチを当てない状態で全ゲートが pass することを先に確かめる。
#
# これが崩れていると、パッチが何もしていなくても全ケースが「主張どおりの層が止めた」に
# なり、表が全部 ✅ で埋まる。たとえば main 側に lint エラーが 1 つ混入するだけで、
# 全ケースが blockedBy: [l1-lint] で match を返す。ケースの判定は、この対照が
# 取れていることの上でしか意味を持たない。
printf '=== baseline（パッチ無し） ===\n' >&2
for gate in "${GATE_ORDER[@]}"; do
  "./scripts/gates/$gate.sh" >"$WORK/baseline-$gate.log" 2>&1
  baseline_code=$?
  if [ "$baseline_code" -ne 0 ]; then
    printf 'エラー: baseline で %s が pass しませんでした（exit %s）\n' "$gate" "$baseline_code" >&2
    printf '  パッチを当てていない状態でゲートが赤いので、ケースの判定は意味を持ちません。\n' >&2
    printf '  先にリポジトリを緑にしてください。\n' >&2
    printf '  完全なログ: %s\n' "$WORK/baseline-$gate.log" >&2
    tail -n 20 "$WORK/baseline-$gate.log" >&2
    exit 2
  fi
done

{
  printf '# 検証結果マトリクス\n\n'
  # シングルクォート内のバッククォートは Markdown のコードスパン表記であり、
  # シェル展開させない意図なので SC2016 は偽陽性（1 行ごとにしか黙らないため個別に付ける）
  # shellcheck disable=SC2016
  printf '`verification/run-all.sh` が生成する。手で編集しない。\n\n'
  printf '「手順書の主張」と「実際に止めた層」を並べるのがこの表の眼目である。\n'
  printf '一致すれば手順書が正しく、ズレれば手順書への修正提案になる。\n\n'
  printf '## この表が保証していること・していないこと\n\n'
  printf '生成前に対照実行（パッチ無しで全ゲートが pass すること）を確認している。\n'
  printf 'したがって ✅ の行は「パッチを当てたら、主張どおりの層のゲートが赤くなった」を意味する。\n'
  printf '❌ と ⚠️ の行はそうならなかったことを意味し、原因の分析は\n'
  # 同上（Markdown のコードスパン表記。展開させない意図）
  # shellcheck disable=SC2016
  printf '`docs/superpowers/phase0-findings.md` の「手順書への修正提案候補」に書く。\n\n'
  printf '一方、次は保証していない。読むときに補って解釈すること。\n\n'
  printf -- '- **どのルールが落としたかは見ていない。** 「実際に止めた層」の列はゲート単位であり、\n'
  printf '  意図したルールが発火したのか、パッチが誘発した別の違反で落ちたのかを区別しない。\n'
  printf '  同じ層で止まる複数のケース（例: L1-01 と L1-02）は観測上まったく同一になる。\n'
  printf -- '- **因果は保証していない。** ゲートが赤くなったことと、それがパッチのせいであることは\n'
  printf '  別である。対照実行はこの隙間を狭めるが、閉じはしない。\n'
  printf -- '- **ゲート単位までは見るが、ルール単位は見ていない。** 手順書がツール名を名指ししている\n'
  # 同上（Markdown のコードスパン表記。展開させない意図）
  # shellcheck disable=SC2016
  printf '  ケースは `claimed_gate` で照合するので「層は一致したが名指しされたツールは無反応」を\n'
  printf '  区別できる。ただし同じゲート内でどのルールが落としたかは区別しない。\n\n'
  printf '| ケース | 落とし穴 | 手順書の主張 | 実際に止めた層 | 判定 |\n'
  printf '|---|---|---|---|---|\n'
} >"$WORK/head.md"

shopt -s nullglob
for case_dir in verification/cases/*/; do
  case_id=$(basename "$case_dir")
  printf '=== %s ===\n' "$case_id" >&2
  stderr_log="$WORK/$case_id.stderr.log"
  ./verification/run-case.sh "$case_id" >"$WORK/$case_id.json" 2>"$stderr_log"
  case_status=$?
  cat "$stderr_log" >&2
  if [ "$case_status" -ne 0 ]; then
    # node_modules の復元失敗（run-case.sh 末尾、pnpm install --frozen-lockfile が
    # 失敗したときのメッセージ）だけは他の exit 2 と同列に扱ってはいけない。
    # 通常の exit 2（判定不能）は次のケースに影響しないが、これは次のケースが
    # 汚染された node_modules の上で走ってしまう（申し送り #17 がまさに防ごうとした
    # 状態）。baseline が赤いときと同じ理由でここも止める。
    #
    # run-case.sh は復元失敗を専用の exit code や TSV では返さない（メッセージでしか
    # 伝えていない）ため、ここではそのメッセージ文字列を判定に使う。run-case.sh 側の
    # 文言を変えるときはこの grep も合わせて直すこと。
    if grep -q 'node_modules を .* の状態へ戻せませんでした' "$stderr_log"; then
      printf 'エラー: %s で node_modules の復元に失敗しました。\n' "$case_id" >&2
      printf '  以降のケースを汚染された node_modules の上で走らせないよう、ここで中断します。\n' >&2
      printf '  復旧: pnpm install --frozen-lockfile\n' >&2
      exit 2
    fi
    printf '| %s | (実行失敗) | | | ⚠️ 実行不能 |\n' "$case_id" >>"$WORK/rows.md"
    continue
  fi
  # シングルクォートは Node の JS リテラル（テンプレートリテラルの ${...} 含む）を
  # シェルに展開させない意図。SC2016 は偽陽性
  # shellcheck disable=SC2016
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    let mark;
    if (r.claimVerdict === "inconclusive") mark = "⚠️ 判定不能";
    else if (r.claimVerdict === "not-caught") mark = "❌ どの層も止めなかった";
    else if (r.claimVerdict === "mismatch") mark = "❌ 別の層が止めた";
    else if (r.claimGateVerdict === "mismatch") mark = "❌ 層は一致・主張したツールは無反応";
    else mark = "✅ 一致";
    const blocked = r.blockedBy.length > 0 ? r.blockedBy.join(", ") : "（なし）";
    // 手順書がツール名まで名指ししているケースは、その名前も併記する
    const claim = r.expected.claimedGate
      ? `${r.expected.claimedLayer} (${r.expected.claimedGate})`
      : r.expected.claimedLayer;
    // 設定の回帰（expect と実測のずれ）は本題ではないので注記として添える
    const notes = [];
    if (r.mismatches.length > 0) {
      notes.push(r.mismatches.map(m => `${m.gate} 期待 ${m.expected} → 実測 ${m.actual}`).join(" / "));
    }
    if (r.detectionMismatches.length > 0) {
      notes.push(r.detectionMismatches.map(m => `${m.gate} 検出 期待 ${m.expected} → 実測 ${m.actual}`).join(" / "));
    }
    const note = notes.length > 0 ? " ※設定ずれ: " + notes.join(" / ") : "";
    // pitfall や注記に | が入ると Markdown の表が壊れるのでエスケープする
    const esc = (s) => String(s).replace(/\|/g, "\\|");
    process.stdout.write(`| ${esc(r.expected.id)} | ${esc(r.expected.pitfall)} | ${esc(claim)} | ${esc(blocked)} | ${esc(mark + note)} |\n`);
  ' "$WORK/$case_id.json" >>"$WORK/rows.md"
done

cat "$WORK/head.md" "$WORK/rows.md" >"$RESULTS"
printf '\n生成しました: %s\n' "$RESULTS" >&2
cat "$RESULTS"
