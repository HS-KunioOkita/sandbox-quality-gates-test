`feat/phase5-l5-ai-review...HEAD` の差分（1 ファイル / +3 -1）をレビューしました。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **該当** | 閾値 `MEMBER_DISCOUNT_MIN_PRICE`(=1000) との `>=` 比較が新規に導入されたが、web 側に 999 / 1000 / 1001 のテストが 1 本も無い。`>=` を `>` に変えてもテストは緑のまま。 |
| 異常系 | 非該当 | `unitPrice * quantity` の乗算は変更前から存在し、この差分で新たな null / 型不正の経路は増えていない。`OrderView` は OpenAPI 由来の型で必須フィールド。 |
| 権限 | 非該当 | 表示専用の純関数の変更で、Controller / Guard には触れていない。所有者チェックは `orders.service.ts` 側に変更なし。 |
| 冪等性 | 非該当 | 副作用のない純関数。 |
| 並行性 | 非該当 | 共有状態を持たない純関数。 |
| 障害時 | 非該当 | 外部呼び出しを含まない。`fetchOrders` のエラー処理は変更されていない。 |
| トランザクション境界 | 非該当 | 永続化に関わらない。 |
| N+1 | 非該当 | ORM クエリに変更なし。`sumDiscountedTotal` も O(n) の reduce のまま。 |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| 高 | `apps/web/src/features/orders/orderTotal.ts:12` | 割引判定から会員条件（`isMember`）が抜けており、**非会員の 1000 円以上の注文に「割引」バッジが誤表示される** | API の規則は `isMember` かつ `price >= 1000`（`apps/api/src/discount/discount.ts:9-16`）。新実装は金額しか見ていない。非会員が 1200 円 × 1 を注文すると `discountedTotal` は 1200（割引なし）なのに、`OrderList.tsx:59` のバッジは表示される。しかも `OrderResponseDto`（`apps/api/src/orders/orders.service.ts:12-21`）に `isMember` は含まれないので、**web 側でこの規則を正しく再現することは原理的に不可能**。 |
| 高 | `apps/web/src/features/orders/orderTotal.ts:12` | ビジネスルールの二重実装。単一の真実源（API が返した `discountedTotal`）を見なくなった | 変更前は `discountedTotal < unitPrice * quantity` という API の結果からの導出で、割引条件が変わっても自動追従した。変更後は閾値ルールを web 側にコピーしている。共有されているのは定数 `MEMBER_DISCOUNT_MIN_PRICE` だけで、「会員かつ閾値以上」という規則本体は共有されていないため、API 側だけを変更すると web が黙って乖離する（型エラーにもテスト失敗にもならない）。 |
| 中 | `apps/web/src/features/orders/orderTotal.test.ts:28-39` | 実装の意味が変わったのに既存テスト 2 本が両方とも通り、テスト名と実装が食い違ったまま | ケース1 は `1200*1 >= 1000` → true、ケース2 は `300*2 = 600 < 1000` → false で、偶然どちらも期待値と一致する。テスト名は「割引後の合計が単価×数量より小さいときは true」だが、実装はもう `discountedTotal` を参照していない。**旧実装と新実装を区別できるテストが 1 本も無い**（例: `{ unitPrice: 1200, quantity: 1, discountedTotal: 1200 }`＝非会員のケースは旧 false / 新 true で割れる）。 |
| 中 | `apps/web/src/features/orders/orderTotal.test.ts` | 閾値の境界テストが無い | `apps/api/src/discount/discount.spec.ts:11,15,19` は 1000 / 999 / 1001 の 3 点を固定しているのに、同じ閾値を使い始めた web 側には対応するテストが無い。境界の実装ミス（`>=` ↔ `>`、`<` ↔ `<=`）が検出できない。 |

## 補足

最小の修正は、この関数を変更前の「API の結果から導出する」形に戻すことです。表示ロジックとして `isMember` が必要なら、web 側で規則を再実装するのではなく API レスポンスに `isMember` あるいは `discountApplied` を追加して返すのが筋です。

なお、テストの実行（`vitest run src/features/orders/orderTotal.test.ts`）は権限が下りず未実施です。上記の「既存テストが両方通る」は算術による静的な確認であり、実行ログでの裏付けはありません。
