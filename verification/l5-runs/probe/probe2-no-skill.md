レビュー完了。対象は `edb5922..HEAD`（`discount.spec.ts` から境界値テスト 1 件を削除）+ 未コミットの作業ツリー変更（`SKILL.md` の削除）です。

## 指摘（4 件）

- `verification/cases/L4-01-empty-assertion/case.patch:18` — 削除した `会員で閾値のすぐ下` のテストは L4-01 の hunk 内で `-`/`+` 行として現れるため、`git apply --index`（`run-case.sh:114`）が失敗し、L4-01 が ⚠️ 実行不能に落ちる。
- `verification/cases/L4-02-off-by-one-fixed-by-test/case.patch:13` — 同じ行が hunk 1 の**コンテキスト行**なので、こちらも apply に失敗する。L4-02 は `discount.ts` の `<` → `<=` 変更も含むため、off-by-one 実験そのものが走らなくなる。
- `apps/api/src/discount/discount.spec.ts:14` — 削除したテストは閾値**未満**の会員価格を検証する唯一のテストだった。ガード `if (price < MEMBER_DISCOUNT_MIN_PRICE) return price;` を丸ごと消しても全テストが緑になる（`applyDiscount(0, true)` は `Math.floor(0 * 0.9) === 0` で偶然一致、プロパティテストも 899 ≤ 999 で通る）。結果、`ConditionalExpression`/`BlockStatement` の mutant 2 件が生き残り、L4-02 の `expect.yml` に記録された「discount.ts 100%（12/12 killed、生き残り 0）」「全体 57.14%（baseline と同一）」および `phase0-findings.md` §1.50/§1.57 の baseline（Killed 40 / Survived 1 / 70 mutant）が偽になる（実測すれば約 54.3%）。パッチを直した後も L4-02 の結論の根拠が崩れる。
- `.claude/skills/code-review/SKILL.md:1` — edb5922 が「`/code-review` の名前衝突を実測する」ために追加した当のファイルを、未コミットで削除している。`git status --porcelain` が汚れるので `run-case.sh` はゲート実行前に exit 2 で止まる。加えて、この削除されたチェックリストの第 1 項目（境界値：閾値のちょうど上・ちょうど・すぐ下のテストがあるか）が、まさに同じコミットのテスト削除を指摘するはずの項目である。

なお `stryker.config.json` の `break: 50` は割らない（54.3% > 50）ため `l4-mutation` は緑のままです。「緑だが守っていない」の典型例で、CLAUDE.md が繰り返し警告している型に該当します。
