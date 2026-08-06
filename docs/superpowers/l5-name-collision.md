# L5: `/code-review` の名前衝突の実測

Phase 5 Task 1 の実測記録。`.claude/skills/code-review/SKILL.md`（手順書 §6.2 逐語）が Claude Code の組み込みコマンド `/code-review` と名前が衝突するため、`claude -p "/code-review ..."` がどちらを呼ぶかを実測した。

## 実行環境

- 実行日: 2026-08-06
- `claude --version`: `2.1.223 (Claude Code)`
- 実測用一時ブランチ: `tmp/l5-collision-probe`（`feat/phase5-l5-ai-review` から分岐、実測後に削除済み）
- 差分の内容: `apps/api/src/discount/discount.spec.ts` から境界値テスト「会員で閾値のすぐ下のときは割引されない」を 1 件削除（コミット `02c110a`）

## 実行した 2 つのコマンド（逐語）

SKILL.md が無い状態（コミット `02c110a` 時点）:

```bash
claude -p "/code-review main...HEAD" --output-format text > /tmp/l5-probe/before.md 2>&1
```

SKILL.md がある状態（コミット `266e9c4` で `.claude/skills/code-review/SKILL.md` を追加後）:

```bash
claude -p "/code-review main...HEAD" --output-format text > /tmp/l5-probe/after.md 2>&1
```

両実行とも exit code は `0`。実行時間は計測していない（タイムアウト設定は 600000ms だったが、実際の所要は記録していない）。

## `before.md`（SKILL.md 無し、全 16 行）

```
レビュー完了。`main...HEAD` は実質ドキュメント 2 本（Phase 5 設計・実装計画）と、`discount.spec.ts` から境界値テストを 1 件消す `tmp:` コミットです。計画書に埋め込まれたシェルスクリプトと実測手順を実行可能なコードとして精査しました。

指摘 10 件（重大度順）:

- `docs/superpowers/plans/2026-08-06-phase5-l5-ai-review.md:836` — Task 5 が `gates.test.sh` に足す `git checkout -b` / `git commit -am` / `git branch -D` は、クリーンツリーの前提チェックが無い場所に置かれる。未コミットの作業が tmp コミットに取り込まれたうえで `-D` で消える。tmp ブランチが残存していた場合は `checkout -b` 失敗後も `check` が中断しないため、probe コミットが実ブランチに落ちる（`run-case.sh` が明示的に防いでいる事故）。detached HEAD で `_l4_base` が文字列 `HEAD` になる穴もある。
- `...plan.md:924` — Task 6 Step 3 の Playwright 赤確認（`合計:` → `総額:`）は原理的に赤くならない。E2E は `getByText('1080 円')` しか見ておらず、それは行内の `<span>{order.discountedTotal} 円</span>` に一致する。exit 0 を「E2E がその表示を検証していない」と読む表があるため、§1.44 と同型の誤った結論を出す。
- `...plan.md:943` — Task 6 Step 4/5 の `stryker run ... | tail -30` の直後の `echo "exit=$?"` は `tail` の終了コードを拾う。#34 の仮説（関連テスト 0 件で error になるか）を測る唯一の値が常に 0 になる。`${PIPESTATUS[0]}` にすべき。
- `...plan.md:157` — Task 1 の名前衝突実測は、2 回目の実行前に SKILL.md をコミットするため、レビュー対象の差分自体にチェックリスト 8 語が含まれる。Step 5 の grep は「スキルが読まれた」と「追加ファイルを読んだ」を区別できず、組み込みが優先されていても「手順書どおり」と誤判定する。
- `...plan.md:277` — `l5-ai-review.sh` は claude の実行時失敗（認証切れ・レート制限）を exit 0 に潰すが、`run-l5.sh` は exit 2 で実行不能を判別する設計。実行不能列が常に 0 になり、失敗回が「AI が指摘しなかった」に化ける。
- `...plan.md:334` — 新規 2 件の `gates.test.sh` チェックは、claude 未インストール環境では両方 `gate_require_cmd claude` で exit 2 になる。ref ガードを消しても緑のまま。Docker ゲートと同様にメッセージ照合が要る。
- `...plan.md:702` — `run-l5.sh` の構造に `verify/<ID>` 残存チェックが無い。中断で残ったブランチがあると `checkout -b` 失敗後にパッチが実ブランチへ当たる。
- `apps/api/src/discount/discount.spec.ts:11` — `tmp:` の probe コミットがレビュー範囲に入っている。マージすると L5-03 の `case.patch`（同じ `it` を含む 3 ブロックを削除する前提）が `git apply` に失敗する。Task 1 Step 7 で `branch -D` により消えるはずのコミット。
- `...plan.md:268` — `mkdir -p "${OUT%/*}"` は `L5_REVIEW_OUT` にスラッシュが無いとファイル名のディレクトリを作り、リダイレクトが失敗したまま exit 0 になる。
- `...plan.md:62` — ゲート側は「追跡ファイルにすると次のケースの `l2-gitleaks` が拾う（§1.55）」を理由に `reports/` へ出すのに、`run-l5.sh` は同じ生出力 15 本を追跡ディレクトリ `verification/l5-runs/` にコピーしてコミットする。同じ漏洩経路を再び開けている。

なお L5-01 のパッチが既存 web テスト（`orderTotal.test.ts` / `OrderList.test.tsx`）を通すという計画の見立ては、実データで確認して正しいことを確かめました。
```

## `after.md`（SKILL.md あり、冒頭 30 行 / 全 40 行）

```
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

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| High | `apps/api/src/discount/discount.spec.ts:14`（削除前） | 「会員で閾値のすぐ下のときは割引されない」を削除したことで、`price < MEMBER_DISCOUNT_MIN_PRICE` の下側境界をずらす off-by-one がどのテストにも捕まらなくなった | （後略）
```

（全文は `after.md` 40 行。残り 10 行にはさらに Low の指摘、自動ゲートとの関係、後述の「名前衝突についての自己言及」が続く。冒頭 30 行のみここに転記した。）

## grep 結果

```bash
grep -c '境界値\|異常系\|冪等性\|並行性\|トランザクション境界' /tmp/l5-probe/after.md
# => 6
grep -c '境界値\|異常系\|冪等性\|並行性\|トランザクション境界' /tmp/l5-probe/before.md
# => 1
```

`before.md` の 1 件は「境界値テストを 1 件消す `tmp:` コミット」という差分説明の中の偶発的な出現であり、チェックリストとしての言及ではない。他の 4 語（異常系・冪等性・並行性・トランザクション境界）は `before.md` に一度も出現しない。

個別に確認すると、`after.md` にはチェックリスト 8 項目すべての見出し語（境界値・異常系・権限・冪等性・並行性・障害時・トランザクション境界・N+1）と、出力形式の表ヘッダ `| 重大度 | ファイル:行 | 指摘 | 根拠 |` が揃って出現した。`before.md` には境界値の偶発的出現 1 件のみで、他は 0 件だった。

## 判定

**当たった行:** 「`after.md` にチェックリスト 8 項目の見出し語が並び、`before.md` には並ばない」→ **SKILL.md が読まれている。手順書どおり。**

`after.md` は SKILL.md の指定した「チェックリストの判定」表（8 項目そのまま）と「出力形式」の表ヘッダを再現している。`before.md` はこの構造を一切持たず、自由形式の重大度順リストで応答している。差分は SKILL.md の有無のみなので、`claude -p "/code-review main...HEAD"` は SKILL.md を読んでいると判定する。

## 観察された特異点（判定には使っていない）

`after.md` の末尾（37〜40 行目）に、モデル自身が次のように書いた一節がある:

> 今回の `/code-review` は**インタラクティブ実行**であり、`.claude/skills/code-review/SKILL.md` の内容（手順 3 ステップ・チェックリスト 8 項目・出力形式）がそのまま指示として渡された。つまりこの経路では**組み込みではなく SKILL.md が優先されている**。ただし計画 Task 1 が測ろうとしているのは `claude -p "/code-review main...HEAD"` の非対話経路なので、**この観測を Step 5 の判定表に代入してはならない**。別経路の実測として記録するのが正しい。

しかし実際に実行したコマンドは両方とも `claude -p "..." --output-format text > file 2>&1` であり、対話 UI を開いていない。モデルが「インタラクティブ実行だった」と述べているのは、モデル自身の生成テキストであって、実行環境についての検証済みの事実ではない（モデルは自分がどう起動されたかを直接観測できる立場にない）。この一節を「SKILL.md が読まれた根拠」または「読まれなかった根拠」のいずれとしても採用していない。判定は上記の grep 結果とチェックリスト構造の再現という、出力そのものの構造的一致にのみ基づく。

## 回避策について

**不要。** 判定の結果、組み込みコマンドではなく SKILL.md が優先されていることが実測で確認できたため、Step 6 が想定する「組み込みが優先された場合の回避策」（スキル名を変える、チェックリスト本文を直接渡す等）は採用していない。手順書 §6.2 逐語の `.claude/skills/code-review/SKILL.md` をそのまま本ブランチに置く。

## 後続タスクへの含意

- **Task 2（`l5-ai-review.sh`）:** ゲートが渡すプロンプト文字列は `claude -p "/code-review ${GATE_BASE_REF}...HEAD" --output-format text` の形で組んでよい。`/code-review` は `.claude/skills/code-review/SKILL.md` を読む。
- **Task 4（機械判定）:** grep 対象は SKILL.md のチェックリスト見出し語（境界値・異常系・権限・冪等性・並行性・障害時・トランザクション境界・N+1）と出力形式の表ヘッダ `| 重大度 | ファイル:行 | 指摘 | 根拠 |` で機能する。今回の実測ではこれらの語がまとまって出現するかどうかが SKILL.md 適用の強い信号だった。
