`/code-review` を差分 `feat/phase5-l5-ai-review...HEAD`（1 commit / 1 ファイル・3 行）に対して実行した。

## 差分の要旨

`apps/web/src/features/orders/orderTotal.ts` の `isDiscountApplied` が、API が返した `discountedTotal` との比較をやめ、**web 側で割引条件を再判定する**実装に変わっている。

```
- return order.discountedTotal < order.unitPrice * order.quantity;
+ return order.unitPrice * order.quantity >= MEMBER_DISCOUNT_MIN_PRICE;
```

割引の仕様は `apps/api/src/discount/discount.ts:applyDiscount` にあり、**「会員であること」かつ「金額が `MEMBER_DISCOUNT_MIN_PRICE` 以上」** の 2 条件である。新しい web 側の判定は後者しか見ていない。

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| High | `apps/web/src/features/orders/orderTotal.ts:12` | 非会員の注文で「割引適用」を誤表示する。合計 1000 円以上なら会員かどうかに関わらず `true` を返す | 仕様は `applyDiscount`（`apps/api/src/discount/discount.ts:10-17`）が持ち、`isMember` が false なら割引されない。`OrderView`（`apps/web/src/api/client.ts:9`）は OpenAPI 由来で `isMember` を含まないため、**web 側だけでは原理的に正しく判定できない**。`OrderList.tsx:59` のバッジ表示が実際の請求額（`discountedTotal`）と矛盾する |
| Medium | `apps/web/src/features/orders/orderTotal.ts:1,12` | 割引条件が API（`discount.ts`）と web の 2 箇所に重複した。API 側の仕様変更（率の変更・段階割引・会員以外への拡大）が web に反映されない | 変更前は `discountedTotal` という API の計算結果だけを見る単一の情報源に依存していた。定数を `@repo/shared` から import しても共有されるのは閾値の値だけで、**判定ロジックそのものは共有されていない** |
| Medium | `apps/web/src/features/orders/orderTotal.test.ts:29-37` | 既存 2 ケースが変更前後の**両方の実装で通る**ため、この挙動変更を 1 件も検出できない | 1 件目は 1200 円（会員・割引あり）で旧実装も新実装も `true`、2 件目は 600 円（閾値未満）でどちらも `false`。**非会員かつ 1000 円以上**という両者が分岐する唯一の入力がテストに存在しない |

## チェックリスト

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **該当** | `MEMBER_DISCOUNT_MIN_PRICE`（1000）を新たに閾値として直接使うようになったのに、999 / 1000 ちょうど / 1001 のテストがない。既存テストの入力は 600 と 1200 のみで、境界は一度も踏まれていない |
| 異常系 | **該当** | 判定に必要な `isMember` が入力型 `OrderView` に存在しない、という入力不足を扱っていない（上表 High）。null / 型不正は OpenAPI 生成型 + TS で担保されており、`quantity: 0` は `0 >= 1000` → `false` で正しいので、この 2 つは問題なし |
| 権限 | 非該当 | 差分は web の純関数のみ。API 側の Controller / Guard と `findOneForUser` の所有者チェック（`orders.service.ts:47-57`）は変更されていない |
| 冪等性 | 非該当 | 引数だけから戻り値が決まる純関数で、副作用も外部呼び出しもない |
| 並行性 | 非該当 | 共有状態への書き込みがない。表示用の派生値の算出のみ |
| 障害時 | 非該当 | 外部サービス呼び出しを含まない。`fetchOrders` のエラー処理（`client.ts:20-22`）は差分外 |
| トランザクション境界 | 非該当 | 永続化を伴わない |
| N+1 | 非該当 | ORM / クエリを触っていない。`sumDiscountedTotal` は取得済み配列の 1 パス集約 |

## 修正方針（参考）

`discountedTotal` との比較に戻すのが最小の修正である。web 側で条件を持ちたい場合は、API のレスポンス DTO に `discountApplied`（あるいは `isMember`）を追加し、判定の情報源を API 側の 1 箇所に保つ必要がある。

なお本差分はこのリポジトリの検証ケース `L5-01-duplicate-logic` の欠陥パッチであるため、**修正は行っていない**（`case.patch` の書き換え禁止・CLAUDE.md）。
