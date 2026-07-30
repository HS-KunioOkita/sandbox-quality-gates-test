#!/usr/bin/env bash
# 全検証ケースを実行し verification/RESULTS.md を生成する。
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

RESULTS=verification/RESULTS.md
WORK=$(mktemp -d)

{
  printf '# 検証結果マトリクス\n\n'
  printf '`verification/run-all.sh` が生成する。手で編集しない。\n\n'
  printf '「手順書の主張」と「実際に止めた層」を並べるのがこの表の眼目である。\n'
  printf '一致すれば手順書が正しく、ズレれば手順書への修正提案になる。\n\n'
  printf '| ケース | 落とし穴 | 手順書の主張 | 実際に止めた層 | 判定 |\n'
  printf '|---|---|---|---|---|\n'
} >"$WORK/head.md"

for case_dir in verification/cases/*/; do
  case_id=$(basename "$case_dir")
  printf '=== %s ===\n' "$case_id" >&2
  if ! ./verification/run-case.sh "$case_id" >"$WORK/$case_id.json"; then
    printf '| %s | (実行失敗) | | | ⚠️ 実行不能 |\n' "$case_id" >>"$WORK/rows.md"
    continue
  fi
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const mark = {
      match: "✅ 一致",
      mismatch: "❌ 別の層が止めた",
      "not-caught": "❌ どの層も止めなかった",
      inconclusive: "⚠️ 判定不能",
    }[r.claimVerdict];
    const blocked = r.blockedBy.length > 0 ? r.blockedBy.join(", ") : "（なし）";
    // 設定の回帰（expect と実測のずれ）は本題ではないので注記として添える
    const note = r.configVerdict === "mismatch"
      ? " ※設定ずれ: " + r.mismatches.map(m => `${m.gate} 期待 ${m.expected} → 実測 ${m.actual}`).join(" / ")
      : "";
    process.stdout.write(`| ${r.expected.id} | ${r.expected.pitfall} | ${r.expected.claimedLayer} | ${blocked} | ${mark}${note} |\n`);
  ' "$WORK/$case_id.json" >>"$WORK/rows.md"
done

cat "$WORK/head.md" "$WORK/rows.md" >"$RESULTS"
printf '\n生成しました: %s\n' "$RESULTS" >&2
cat "$RESULTS"
