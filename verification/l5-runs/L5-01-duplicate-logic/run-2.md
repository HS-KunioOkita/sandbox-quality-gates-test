`feat/phase5-l5-ai-review...HEAD` の差分は 1 ファイル 3 行（`apps/web/src/features/orders/orderTotal.ts`）。`isDiscountApplied` が API の `discountedTotal` を見る実装から、web 側で割引条件を再判定する実装に変わっている。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **該当** | 新たに `>= MEMBER_DISCOUNT_MIN_PRICE`(1000) の閾値比較を導入したのに、999 / 1000 / 1001 のいずれのテストも無い。既存 2 ケースは 1200 と 600（下記 #3） |
| 異常系 | 非該当 | 追加した分岐は number 同士の比較のみ。`OrderView` は OpenAPI 生成型（`schema.d.ts:43-51`）で `unitPrice` / `quantity` とも必須 number、null / 型不正は型上入らない。`quantity: 0` は `0 >= 1000` で false になり破綻しない |
| 権限 | 非該当 | Controller / API 側は無変更。差分は表示用の純関数のみで、`orders.service.ts:findOneForUser` の所有者チェックには触れていない |
| 冪等性 | 非該当 | 副作用もリクエスト発行も無い純関数 |
| 並行性 | 非該当 | 状態を持たず、共有リソースへの書き込みが無い |
| 障害時 | 非該当 | 外部呼び出しは増えていない。`fetchOrders` の失敗経路（`OrderList.tsx:28-33`）は未変更 |
| トランザクション境界 | 非該当 | DB 書き込みを含まない |
| N+1 | 非該当 | ORM クエリは不変。描画時に注文件数分の算術が走るだけ |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| High | `apps/web/src/features/orders/orderTotal.ts:12` | 非会員の注文に「割引」バッジが誤表示される。API の割引条件は `isMember && price >= 1000` の AND だが、web 側の再判定は金額条件しか見ていない | `apps/api/src/discount/discount.ts:11-13` が `if (!isMember) return price;` で会員条件を先に見ている。一方 `OrderResponseDto`（`order-response.dto.ts` / `schema.d.ts:43-51`）に会員フラグは無く、**web 側は原理的にこの条件を再現できない**。具体例: 非会員 + `unitPrice:1200, quantity:1` → API は `discountedTotal: 1200`（割引なし）を返すのに `isDiscountApplied` は true。画面には「1200 円」と「割引」が同時に出る（`OrderList.tsx:59-63`） |
| High | `apps/web/src/features/orders/orderTotal.ts:12` | 割引ルールが API と web に二重化した。閾値・端数処理・条件追加のたびに 2 箇所を同期する必要があり、片方だけ変えても typecheck も既存テストも通る | 変更前の `order.discountedTotal < order.unitPrice * order.quantity` は API の出力そのものを見ていたので、`discount.ts` のルール変更に自動追従していた。変更後は `MEMBER_DISCOUNT_MIN_PRICE` だけを共有し、`MEMBER_DISCOUNT_RATE`・`Math.floor` の切り捨て・会員条件は共有していない。権威は `discount.ts` 側にあり、web はその部分コピーになっている |
| Medium | `apps/web/src/features/orders/orderTotal.test.ts:31-41` | 振る舞いを変えたのに、既存テストが 1 本も落ちない。このテストは変更前の契約を固定できていない | 既存 2 ケースは変更前後どちらの実装でも通る（`1200*1 >= 1000` → true / `300*2 >= 1000` → false、いずれも期待値と一致）。`OrderList.test.tsx:55-62` も同じ fixture（1200×1 と 300×2）で同様。境界の 1000 ちょうど、直下の 999、直上の 1001 のどれも踏んでいない。※実行環境の都合でテストは実測せず、静的に確認した |
| Low | `apps/web/src/features/orders/orderTotal.test.ts:32,37` | テスト名が実装の満たさない契約を述べている（「割引後の合計が単価×数量より小さいときは true」）。実装は `discountedTotal` を参照しなくなった | 名前が実際に固定している内容とずれると、以後このテストが赤くなったときに何が壊れたのか読めなくなる。スタイルではなく「テストが何を保証しているかの表示」の問題として挙げる |

補足（問題なしを確認した点）: 閾値の比較対象は API 側も `applyDiscount(order.unitPrice * order.quantity, ...)`（`orders.service.ts:20`）で小計基準なので、**金額の計算基準そのものはずれていない**。ずれているのは会員条件の有無だけ。

修正方針としては、元の `discountedTotal < unitPrice * quantity` に戻すのが最小かつ、上記 High 2 件を同時に消す。web で判定し続けたいなら `OrderResponseDto` に `discountApplied: boolean` を API 側で載せるのが筋（会員情報を web に流さずに済む）。
