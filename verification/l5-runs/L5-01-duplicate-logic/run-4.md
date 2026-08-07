テストの実行は許可が下りなかったため、以下は差分と関連コードの読解による判定です（`vitest` 未実行）。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **該当** | この差分で `MEMBER_DISCOUNT_MIN_PRICE`（1000）との比較が web 側に新設されたのに、`orderTotal.test.ts` のケースは 1200（上）と 600（下）だけ。ちょうど 1000 と 999 のテストがない。API 側（`discount.spec.ts:11,15,19`）は 1000 / 999 / 1001 を持っており、web 側だけ境界が固定されていない |
| 異常系 | 非該当 | `OrderView` は OpenAPI 生成型で `unitPrice` / `quantity` は `number` 固定。null / 空 / 型不正の入力経路がない。空配列は `sumDiscountedTotal` 側で既にテスト済み（`orderTotal.test.ts:19`） |
| 権限 | 非該当 | 差分は web の純関数 1 本のみ。Controller / Guard に変更なし。表示するのは自分の注文一覧に対するバッジで、他ユーザーのリソースには触れない |
| 冪等性 | 非該当 | 副作用のない純関数。リクエストを発行しない |
| 並行性 | 非該当 | 共有状態を持たない。`OrderList` の `cancelled` フラグによる競合対策は差分の対象外で変更なし |
| 障害時 | 非該当 | `fetchOrders` の失敗処理（`OrderList.tsx:26-30`）は未変更。この関数は取得済みデータのみを見る |
| トランザクション境界 | 非該当 | DB 更新を含まない |
| N+1 | 非該当 | ORM を呼ばない。API 側の `include: { user: true }`（`orders.service.ts:29`）も未変更 |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| **High** | `apps/web/src/features/orders/orderTotal.ts:12` | 非会員の注文でも小計が 1000 円以上なら「割引」バッジが出る（誤表示） | API の割引条件は `isMember && price >= MEMBER_DISCOUNT_MIN_PRICE`（`apps/api/src/discount/discount.ts:10-15`）で、会員判定が必須。新実装は小計の閾値だけを見て `isMember` を落としている。非会員の 1200 円の注文は `discountedTotal === 1200`（割引なし）なのに `isDiscountApplied` が `true` を返し、`OrderList.tsx:59-61` が「割引」を表示する |
| **High** | `apps/web/src/features/orders/orderTotal.ts:12` | そもそも web 側では正しく再判定できない。`OrderView` に会員情報が無い | `OrderView` は `paths['/orders']['get']...` から導出される OpenAPI 生成型（`apps/web/src/api/client.ts:9-10`）で、`OrderResponseDto` のフィールドは `id` / `productName` / `unitPrice` / `quantity` / `status` / `discountedTotal` のみ（`orders.service.ts:13-20`）。`isMember` は API 内部にしか無い。修正方向は「web で条件を足す」ではなく、変更前の `order.discountedTotal < order.unitPrice * order.quantity` に戻す（API が算出した結果を単一の真実として使う）こと |
| **Medium** | `apps/web/src/features/orders/orderTotal.ts:11-12` | 割引ルールの実装が API と web の 2 箇所に分裂する。`@repo/shared` が共有しているのは閾値の数値だけで、条件式（比較の向き・会員必須・課税基準が小計か単価か・`MEMBER_DISCOUNT_RATE`）は共有されていない | API 側でルールが変わっても web は追従しない。例: 割引基準を小計から単価（`unitPrice >= 1000`）に変えた場合、`applyDiscount` を直せば API は正しくなるが web のバッジだけ静かに乖離する。`l1-typecheck` も `l3-test` もこの乖離を検知しない（型が同じで、既存テストは後述のとおり通る） |
| **Medium** | `apps/web/src/features/orders/orderTotal.test.ts:28-40` | 既存の 2 ケースは実装を変えても両方通るため、この欠陥を固定していない。加えてテスト名が実装と矛盾している | `1200 × 1 = 1200 >= 1000` → `true`、`300 × 2 = 600 >= 1000` → `false` で、いずれも期待値どおり通る。閾値の同じ側／反対側に偶然分かれているだけ。さらに「割引後の合計が単価×数量より小さいときは true」という名前に対し、新実装は `discountedTotal` を一切参照しない。**非会員 × 小計 1000 円以上（`discountedTotal === unitPrice * quantity`）のケースを追加すれば赤くなる**が、それは会員情報が型に無いため web の単体テストでは表現できず、指摘 2 の結論（API 結果を使う実装に戻す）を裏付ける |

**要約**: この差分は API が算出済みの `discountedTotal` を捨てて割引条件を web 側で再実装しており、`isMember` を表現できないため非会員に誤って「割引」を表示します。既存テストは通るので、変更前の `discountedTotal` 比較に戻すのが正しい修正です。
