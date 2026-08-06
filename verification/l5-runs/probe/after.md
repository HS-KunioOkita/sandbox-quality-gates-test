## 差分の範囲

```
.claude/skills/code-review/SKILL.md                |   23 +   (新規)
apps/api/src/discount/discount.spec.ts             |    4 -   (テスト 1 件削除)
docs/superpowers/plans/2026-08-06-phase5-l5-ai-review.md  | 1223 +  (新規・ドキュメント)
docs/superpowers/specs/2026-08-06-phase5-l5-ai-review-design.md | 156 +  (新規・ドキュメント)
```

実行コードの変更は **`discount.spec.ts` からのテスト 1 件削除のみ**。残り 3 ファイルはドキュメントとスキル定義。

## チェックリストの判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **該当** | 閾値ちょうど（1000）とすぐ上（1001）は残っているが、**すぐ下（999）のテストが削除された**。`applyDiscount` の分岐は `price < MEMBER_DISCOUNT_MIN_PRICE` の 1 箇所で、下側境界を固定するテストが差分適用後は 1 件も無い（→ 指摘 1） |
| 異常系 | **該当（軽微・既存）** | `applyDiscount` に負値 / 非整数 / `NaN` の例示テストが無い。プロパティテストは `fc.integer({ min: 0, max: 1_000_000 })` に限定されており、`applyDiscount(-500, true)` が `-500` を返す挙動を誰も固定していない。ただしこれは差分が持ち込んだものではなく既存のギャップ（→ 指摘 3） |
| 権限 | 非該当 | Controller・Guard・認可ロジックのファイルが差分に一切含まれていない。`orders.controller.ts` は未変更 |
| 冪等性 | 非該当 | リクエストを受ける経路（Controller / Service / Prisma 呼び出し）の変更が無い。`applyDiscount` は引数のみに依存する純関数で、副作用も外部状態も持たない |
| 並行性 | 非該当 | 共有状態・書き込み・ロックに関わる変更が無い。削除されたのはテストコードのみ |
| 障害時 | 非該当 | 外部サービス呼び出しの追加・変更が無い。SKILL.md は Claude Code のスキル定義でありアプリの実行経路に入らない |
| トランザクション境界 | 非該当 | 複数テーブル更新のコードが差分に含まれていない。Prisma の呼び出し箇所は未変更 |
| N+1 | 非該当 | ORM クエリの変更が無い。`orders.service.ts` は未変更（設計書 §4.3 が `L5-02` で N+1 を注入する予定としているが、この差分には含まれていない） |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| High | `apps/api/src/discount/discount.spec.ts:14`（削除前） | 「会員で閾値のすぐ下のときは割引されない」を削除したことで、`price < MEMBER_DISCOUNT_MIN_PRICE` の下側境界をずらす off-by-one がどのテストにも捕まらなくなった | 削除後に `isMember=true` で 1〜999 を通す例示テストは 0 件（残るのは 1000 / 1001 / 1005 / 0）。仮に条件を `price < MEMBER_DISCOUNT_MIN_PRICE - 1` に変えると `applyDiscount(999, true)` は 999 → 899 になるが、プロパティテスト 3 本の主張（`result <= price` / 非負整数 / 非会員は恒等）はすべて 899 で成立するため通過する。`0 円は割引されない` も `0 < 999` で真のまま通る。**閾値の直下は「割引されない」側の唯一の代表点であり、これを消すと閾値の位置そのものが未固定になる** |
| High | `apps/api/src/discount/discount.spec.ts` | このテスト削除は commit 02c110a `tmp: 境界値テストを 1 件削除（衝突実測用）` の一時変更であり、**main にマージしてはならない** | 実装計画 Task 1 Step 7 は `git branch -D tmp/l5-collision-probe` でこのブランチを破棄し、SKILL.md のみを `feat/phase5-l5-ai-review` に置き直すと定めている。また設計書 §4.3 は同じ欠陥を `verification/cases/L5-03-missing-boundary-test/case.patch`（境界値 **3 件**削除）として入れる設計であり、ソースツリー直接編集は想定されていない |
| Medium | `.claude/skills/code-review/SKILL.md:6` | 手順 1 が比較対象を `origin/main` にハードコードしているため、`l5-ai-review.sh` がプロンプト引数で渡す `GATE_BASE_REF` と食い違いうる。指示に忠実に従うと引数を無視して `origin/main...HEAD` を見ることになり、レビュー対象の差分範囲が変わる | 設計書 §4.1「`l5-ai-review.sh` の比較対象は `GATE_BASE_REF` で受け取る」に対し、SKILL.md 本文は固定値。手順書 §6.2 の逐語であることが検証の前提（計画 Task 1 Step 3「改善・補足を加えてはいけない」）なので**修正すべきではなく、手順書側の穴として記録する対象**。検証ブランチが `origin/main` から派生している間は実害が出ないため気づきにくい |
| Low | `apps/api/src/discount/discount.spec.ts:36-42` | プロパティテストの入力域が `min: 0` に限られており、負値の扱いが仕様として固定されていない。`applyDiscount(-500, true)` は現状 `-500` を返すが、これが意図した挙動かテストからは読めない（既存のギャップ。差分起因ではない） | `fc.integer({ min: 0, max: 1_000_000 })` が 3 本すべてに使われている。`discount.ts` の JSDoc も負値について何も述べていない |

## 自動ゲートとの関係（参考）

この差分は `apps/api/src` の **spec のみ**を変更しているため、設計書 §2 の表のとおり `stryker-diff.sh` は `L4_MUTATE_FILES=(none)` でスキップされ、`l4-mutation` は緑を返す。L1〜L3 も spec 1 件の削除では赤くならない。**上記 High 1 件目を止める自動ゲートは現状 1 本も無い** —— これは設計書 §4.3 が `L5-03` に期待した構造（L1〜L4 全緑 → `not-caught`）と一致する。

## 名前衝突について（§4.2 関連の観測）

今回の `/code-review` は**インタラクティブ実行**であり、`.claude/skills/code-review/SKILL.md` の内容（手順 3 ステップ・チェックリスト 8 項目・出力形式）がそのまま指示として渡された。つまりこの経路では**組み込みではなく SKILL.md が優先されている**。ただし計画 Task 1 が測ろうとしているのは `claude -p "/code-review main...HEAD"` の非対話経路なので、**この観測を Step 5 の判定表に代入してはならない**。別経路の実測として記録するのが正しい。
