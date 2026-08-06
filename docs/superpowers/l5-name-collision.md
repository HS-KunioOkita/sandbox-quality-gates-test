# L5: `/code-review` の名前衝突の実測

Phase 5 Task 1 の実測記録。`.claude/skills/code-review/SKILL.md`（手順書 §6.2 逐語）が Claude Code の組み込みコマンド `/code-review` と名前が衝突するため、`claude -p "/code-review ..."` がどちらを呼ぶかを実測した。

**実測は 2 回に分かれている。** 1 回目（before/after 比較）は判定の根拠が交絡していたことが fix round 1 のレビューで判明したため、2 回目（probe A/B）で交絡を切って再実測した。**1 回目の記録は削除せず、そのまま残す。** 誤った判定に至りかけた経路自体が記録価値を持つため。

**最終的な判定は 2 回目（probe A/B）の観測を根拠にする。** 1 回目は参考記録であり、判定には使わない。

## 生出力の保存先

実行した `claude -p` の生出力 4 本は追跡ファイルとして保存してある。全文はここに転記せず、以下のパスを参照する。

- `verification/l5-runs/probe/before.md`（1 回目・SKILL.md 無し）
- `verification/l5-runs/probe/after.md`（1 回目・SKILL.md あり、ただし交絡あり）
- `verification/l5-runs/probe/probe2-with-skill.md`（2 回目・probe A・SKILL.md あり）
- `verification/l5-runs/probe/probe2-no-skill.md`（2 回目・probe B・SKILL.md 無し）

## 実行環境（共通）

- 実行日: 2026-08-06
- `claude --version`: `2.1.223 (Claude Code)`

---

## 第 1 回実測（before / after 比較）——交絡あり

### 実測用一時ブランチ

`tmp/l5-collision-probe`（`feat/phase5-l5-ai-review` から分岐、実測後に削除済み）。差分の内容: `apps/api/src/discount/discount.spec.ts` から境界値テスト「会員で閾値のすぐ下のときは割引されない」を 1 件削除（コミット `02c110a`）。

### 実行した 2 つのコマンド（逐語）

SKILL.md が無い状態（コミット `02c110a` 時点）:

```bash
claude -p "/code-review main...HEAD" --output-format text > /tmp/l5-probe/before.md 2>&1
```

SKILL.md がある状態（コミット `266e9c4` で `.claude/skills/code-review/SKILL.md` を追加後）:

```bash
claude -p "/code-review main...HEAD" --output-format text > /tmp/l5-probe/after.md 2>&1
```

両実行とも exit code は `0`。実行時間は計測していない。

### 出力の概要

- `before.md`（全 16 行、`verification/l5-runs/probe/before.md`）: 自由形式の重大度順リスト（`指摘 10 件（重大度順）:` で始まる）。SKILL.md のチェックリスト構造・出力形式は現れない。
- `after.md`（全 40 行、`verification/l5-runs/probe/after.md`）: 「差分の範囲」「チェックリストの判定」（8 項目の表）「指摘」（`| 重大度 | ファイル:行 | 指摘 | 根拠 |` 形式の表）「自動ゲートとの関係」「名前衝突についての自己言及」の構成。

### grep 結果

```bash
grep -c '境界値\|異常系\|冪等性\|並行性\|トランザクション境界' /tmp/l5-probe/after.md   # => 6
grep -c '境界値\|異常系\|冪等性\|並行性\|トランザクション境界' /tmp/l5-probe/before.md  # => 1
```

`after.md` にはチェックリスト 8 項目すべての見出し語と出力形式の表ヘッダが揃って出現し、`before.md` には「境界値」の偶発的な出現 1 件（差分説明の地の文）のみだった。

### この実測の交絡（fix round 1 で判明）

**この 1 回目の実測は判定として使えない。** brief の Step 4 の手順は、`SKILL.md` をコミットしてから `main...HEAD` を diff する。そのため after 側の実行では、**レビュー対象の差分そのものに SKILL.md の全文（チェックリスト 8 項目を含む）が含まれていた**（`after.md` の「差分の範囲」節に `.claude/skills/code-review/SKILL.md | 23 + (新規)` と明記されている）。

したがって、出力にチェックリストが現れたことは次の 2 つのどちらでも説明でき、この実測だけでは区別できない。

- (a) `/code-review` がスキルを読み込み、チェックリストに従って出力した
- (b) モデルが「差分に含まれていたチェックリストを書いたファイル」を単に読んで、その構造を模倣しただけ（SKILL.md はスキルとして実行されていない）

**`before.md` 自身がこの欠陥を明示的に指摘していた。** `before.md` の指摘の 1 つ（4 番目）は次のとおり:

> `...plan.md:157` — Task 1 の名前衝突実測は、2 回目の実行前に SKILL.md をコミットするため、レビュー対象の差分自体にチェックリスト 8 語が含まれる。Step 5 の grep は「スキルが読まれた」と「追加ファイルを読んだ」を区別できず、組み込みが優先されていても「手順書どおり」と誤判定する。

初回の記録作成時（このドキュメントの初版）はこの指摘を見落とし、grep 結果とチェックリスト構造の再現だけを根拠に「SKILL.md が読まれている」と判定していた。この判定は交絡のため無効であり、2 回目の実測（下記）で再確認する必要があった。

### 観察された特異点（いずれの判定にも使っていない）

`after.md` の末尾に、モデル自身が次のように書いた一節がある:

> 今回の `/code-review` は**インタラクティブ実行**であり、`.claude/skills/code-review/SKILL.md` の内容（手順 3 ステップ・チェックリスト 8 項目・出力形式）がそのまま指示として渡された。つまりこの経路では**組み込みではなく SKILL.md が優先されている**。ただし計画 Task 1 が測ろうとしているのは `claude -p "/code-review main...HEAD"` の非対話経路なので、**この観測を Step 5 の判定表に代入してはならない**。別経路の実測として記録するのが正しい。

しかし実際に実行したコマンドは両方とも `claude -p "..." --output-format text > file 2>&1` であり、対話 UI は開いていない。モデルが「インタラクティブ実行だった」と述べているのは、モデル自身の生成テキストであって、実行環境についての検証済みの事実ではない（モデルは自分がどう起動されたかを直接観測できる立場にない）。この一節はどちらの判定にも採用していない。

---

## 第 2 回実測（probe A / B）——交絡を切った実測

### 設計

1 回目の交絡は「SKILL.md の追加そのものが diff に入ってしまう」ことが原因だった。これを避けるため、**すでに SKILL.md を含むコミット（`edb5922`）を比較の基点にする**。この基点から先で SKILL.md に変更を加えずにテストを 1 件削除すれば、diff（`edb5922...HEAD`）に SKILL.md は一切現れない。

- **probe A（スキルあり）:** 作業ツリーに `.claude/skills/code-review/SKILL.md` を置いたまま実行
- **probe B（スキルなし）:** `.claude/skills/code-review` を作業ツリーから一時退避（コミットしない）してから実行

A と B は同一コミット・同一 diff（`edb5922...HEAD`）に対する実行であり、差はスキルディレクトリの有無だけになる。

### 実行した手順（逐語）

```bash
git checkout -b tmp/l5-probe2
# apps/api/src/discount/discount.spec.ts から
#   it('会員で閾値のすぐ下のときは割引されない', ...) の1ブロックのみ削除
git commit -am "tmp: 境界値テストを 1 件削除（交絡を切った実測用）"
# => コミット 7c440e2
git diff edb5922...HEAD   # SKILL.md は含まれず、discount.spec.ts の4行削除のみであることを確認
```

**probe A（スキルあり）:**

```bash
claude -p "/code-review edb5922...HEAD" --output-format text > /tmp/l5-probe/probe2-with-skill.md 2>&1
```
→ exit 0、30 行。

**probe B（スキルなし・diff は A と完全に同一）:**

```bash
mv .claude/skills/code-review /tmp/skill-backup
claude -p "/code-review edb5922...HEAD" --output-format text > /tmp/l5-probe/probe2-no-skill.md 2>&1
mv /tmp/skill-backup .claude/skills/code-review
git status --porcelain   # 空であることを確認
```
→ exit 0、10 行。退避直後に復元し、`git status --porcelain` が空であることを確認済み。

後始末:

```bash
git checkout feat/phase5-l5-ai-review
git branch -D tmp/l5-probe2
```

### 出力の要点

**probe A**（`verification/l5-runs/probe/probe2-with-skill.md`、全 30 行）冒頭:

> `.claude/skills/code-review` の手順に従ってレビューしました。差分は引数で指定された `edb5922...HEAD` を対象にしています（`origin/main...HEAD` にすると L5 スキル本体と docs 4 ファイルも含まれますが、指定範囲は 1 コミット・テスト 4 行削除のみ）。

以降「チェックリスト」節に 8 項目の判定表、「指摘」節に `| 重大度 | ファイル:行 | 指摘 | 根拠 |` 形式の表が続く。境界値の該当理由として「削除により『すぐ下（999）』を検証するテストがリポジトリ全体から消えた」と明記し、`discount.ts` の off-by-one が全テストをすり抜けることを指摘した（重大度: 高）。

**probe B**（`verification/l5-runs/probe/probe2-no-skill.md`、全 10 行）冒頭:

> レビュー完了。対象は `edb5922..HEAD`（`discount.spec.ts` から境界値テスト 1 件を削除）+ 未コミットの作業ツリー変更（`SKILL.md` の削除）です。

以降「指摘（4 件）」という自由形式の箇条書きで、チェックリスト構造も出力形式の表も現れない。なお指摘 3 件目・4 件目は、`.claude/skills/code-review/SKILL.md` 自体が作業ツリー上で削除されていること（= probe B が仕掛けた退避操作そのもの）を差分の一部として検出し、その内容（チェックリスト第 1 項目の文言）に言及している。これはスキルとして実行されたのではなく、削除された `SKILL.md` というファイルの内容を diff 越しに読んだ結果であり、probe A のチェックリスト運用とは区別できる。

### grep 比較

```bash
for kw in 境界値 異常系 権限 冪等性 並行性 障害時 トランザクション境界 'N+1'; do
  echo "$kw: with-skill=$(grep -c "$kw" probe2-with-skill.md) no-skill=$(grep -c "$kw" probe2-no-skill.md)"
done
```

| 見出し語 | probe A（あり） | probe B（無し） |
|---|---|---|
| 境界値 | 2 | 2（※） |
| 異常系 | 1 | 0 |
| 権限 | 1 | 0 |
| 冪等性 | 1 | 0 |
| 並行性 | 1 | 0 |
| 障害時 | 1 | 0 |
| トランザクション境界 | 1 | 0 |
| N+1 | 1 | 0 |
| 出力形式ヘッダ `\| 重大度 \| ファイル:行 \| 指摘 \| 根拠 \|` | 1 | 0 |

（※）probe B の「境界値」2 件は、削除したテストの内容を地の文で説明している箇所であり、チェックリスト項目としての出現ではない（「境界値：閾値のちょうど上・ちょうど・すぐ下のテストがあるか」という定型文はゼロ件）。

### 判定

**当たった行:** 「A にチェックリスト 8 項目が並び、B には並ばない」→ **SKILL.md が読まれている（交絡なしで確定）。**

probe A・B の diff は `edb5922...HEAD` で完全に同一であり、違いは作業ツリーに SKILL.md があるかどうかだけである。A は 8 項目の判定表と出力形式ヘッダを完全に再現し、B はいずれも再現していない。1 回目の交絡（SKILL.md の追加自体が diff に入る）を除いた条件でも同じ結論に至った。

---

## 最終的な結論

`claude -p "/code-review <base>...HEAD" --output-format text` は `.claude/skills/code-review/SKILL.md` を読み、チェックリスト構造と出力形式に従う。組み込みコマンドは優先されない。この結論は交絡を切った第 2 回実測（probe A/B）を根拠にしている。第 1 回実測（before/after）は同じ結論を示していたが、判定の根拠としては交絡があったため無効であり、参考記録として残すのみである。

## 回避策について

**不要。** SKILL.md が優先されると実測で確認できたため、「組み込みが優先された場合の回避策」（スキル名を変える、チェックリスト本文を直接渡す等）は採用していない。手順書 §6.2 逐語の `.claude/skills/code-review/SKILL.md` をそのまま本ブランチに置く。

## 後続タスクへの含意

- **Task 2（`l5-ai-review.sh`）:** ゲートが渡すプロンプト文字列は `claude -p "/code-review ${GATE_BASE_REF}...HEAD" --output-format text` の形で組んでよい。`/code-review` は `.claude/skills/code-review/SKILL.md` を読む。
- **Task 4（機械判定）:** grep 対象は SKILL.md のチェックリスト見出し語（境界値・異常系・権限・冪等性・並行性・障害時・トランザクション境界・N+1）と出力形式の表ヘッダ `| 重大度 | ファイル:行 | 指摘 | 根拠 |` で機能する。ただし「境界値」のような単語は地の文にも偶発的に出現しうる（probe B で実測済み）ので、機械判定は単語の出現有無だけでなく、チェックリスト表形式（`| 項目 | 判定 | 理由 |` 等の構造）や複数語の同時出現で判定する方が頑健と考えられる。
