`pnpm exec vitest` の実行は承認されなかったので、テスト結果は**コードを読んだ上での導出**であり実測ではありません（該当箇所で明示します）。

## スコープの確認

指定範囲 `feat/phase5-l5-ai-review...HEAD` の実体は **1 ファイル・3 挿入 1 削除**、`L5-01-duplicate-logic` の欠陥パッチそのものです。現在のブランチ `verify/l5-L5-01-duplicate-logic` は `run-l5.sh` が作った検証用ブランチが残ったもので、Phase 5 の実装（ゲート・ハーネス・ケース定義）はこの範囲に含まれません。Phase 5 の実装をレビューしたい場合は `main...feat/phase5-l5-ai-review`（17 ファイル）を指定してください。

以下は指定どおり、注入された欠陥差分に対するレビューです。

## チェックリスト

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **該当** | 閾値 `MEMBER_DISCOUNT_MIN_PRICE = 1000` を新たに参照するのに、999 / 1000 / 1001 のテストが無い。既存は 600 と 1200 のみ |
| 異常系 | 非該当 | 入力は `OrderView`（全項目 non-nullable）。`unitPrice`/`quantity` が 0 でも `0 >= 1000` が false になるだけで破綻しない。空配列は `sumDiscountedTotal` 側で既にカバー済み |
| 権限 | 非該当 | 変更はフロントの純関数のみ。Controller / Guard に触れていない。ただし後述のとおり「会員かどうか」という**権限に近い属性をクライアントが持っていない**ことが本質的な問題 |
| 冪等性 | 非該当 | 副作用のない純関数。同じ入力に同じ出力 |
| 並行性 | 非該当 | 共有状態の更新なし |
| 障害時 | **該当（軽）** | 外部呼び出しは無いが、API 側の割引ルール変更に対して web が黙って食い違う（後述 #4） |
| トランザクション境界 | 非該当 | 永続化に関与しない |
| N+1 | 非該当 | `reduce` / `map` は件数に対して線形。クエリを発行しない |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| **高** | `apps/web/src/features/orders/orderTotal.ts:12` | 判定条件から `isMember` が抜けている。**非会員の 1000 円以上の注文すべてに割引バッジが誤表示される** | API の真の条件は `applyDiscount()` = 「`isMember` かつ `price >= 1000`」（`apps/api/src/discount/discount.ts:10-16`）。web 側は後者しか見ない。非会員は `discountedTotal === unitPrice * quantity` なのに `OrderList.tsx:59` がバッジを描画する |
| **高** | `apps/web/src/features/orders/orderTotal.ts:12` | この誤りは web 側だけでは**修正不可能**。`OrderView` に `isMember` が存在しない | `OrderView` は `paths['/orders']['get']` のレスポンス型（`apps/web/src/api/client.ts:9-10`）で、実体は `OrderResponseDto`。フィールドは id / productName / unitPrice / quantity / status / discountedTotal のみで会員フラグを含まない。サーバが計算した `discountedTotal` と比較する変更前の実装が、クライアントが正しく判定できる唯一の形だった |
| **中** | `apps/web/src/features/orders/orderTotal.test.ts:28-40` | 既存 2 テストがこの変更を検出しない（実装を壊してもテストが赤くならない）。さらにテスト名が実装と乖離した | 1200×1 → 新実装 `1200 >= 1000` = true / 旧実装 `1080 < 1200` = true。600 → 新 `600 >= 1000` = false / 旧 `600 < 600` = false。**両ケースとも新旧で一致するため素通りする**（コード読解による導出。vitest 実行は未承認のため未実測）。加えてテスト名「割引後の合計が単価×数量より小さいときは true」は、新実装が `discountedTotal` を一切参照しないため事実に反する |
| **中** | `apps/web/src/features/orders/orderTotal.test.ts` | 不足しているテスト: ①非会員 × subtotal ≥ 1000（`discountedTotal === unitPrice * quantity`）で false であること ②境界 999 / 1000 / 1001 | ①が本欠陥を捕まえる唯一のケース。②は `>=` の向き（API の `if (price < MIN) return price` と一致すること）を固定する |
| **中** | `apps/web/src/features/orders/orderTotal.ts:12` | 割引ルールが API と web の 2 箇所に分散した。閾値・割引率・端数処理（`Math.floor`）のいずれかが API 側で変わると、web 再デプロイまで表示が黙って食い違う | 変更前はサーバの計算結果と比較していたため、ルール変更に構造的に追従した。`MEMBER_DISCOUNT_MIN_PRICE` を共有パッケージから import しても、共有できるのは定数だけで**条件式そのもの（`isMember` の AND）は共有されていない** |

## 推奨

`isDiscountApplied` を変更前の形（`order.discountedTotal < order.unitPrice * order.quantity`）に戻すのが正解です。どうしても宣言的に持たせたいなら、判定を API 側に寄せて `OrderResponseDto` に `discountApplied: boolean` を追加する形にしてください。`isMember` をクライアントに出して再計算させる方向は、上記 #4 のドリフト問題が残るので勧めません。

---

なお、この差分は L5 検証ケースとして意図的に注入された欠陥です。上のレビューは対話セッションでの手動実行なので、`l5-ai-review` ゲートの実測データとしては使えません（ゲートは fresh な非対話セッションで走る前提）。また `verify/l5-L5-01-duplicate-logic` ブランチが残っているので、`run-l5.sh` の後始末が漏れていないか確認しておくとよいです。
