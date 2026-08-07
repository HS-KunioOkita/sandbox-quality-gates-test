差分は 1 ファイル 3 行だが、`isDiscountApplied` の判定根拠を「API のレスポンス」から「web 側での条件再計算」に変えている。呼び出し元と API 側の権威ロジックを確認した。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **該当** | `MEMBER_DISCOUNT_MIN_PRICE`（1000）が新たに比較演算子の対象になったが、ちょうど 1000 / 999 / 1001 のテストが無い（指摘 2） |
| 異常系（null / 空 / 型不正 / 上限超過） | 非該当 | `OrderView` は OpenAPI 由来の型で `unitPrice` / `quantity` は必須 number。空配列は `sumDiscountedTotal` 側で既にテスト済み（`orderTotal.test.ts:17`）。差分は異常系の扱いを変えていない |
| 権限 | 非該当 | 差分は web の表示判定のみ。API の所有者チェック（`orders.service.ts:53` の `order.userId !== userId` → 403）に変更なし |
| 冪等性 | 非該当 | `isDiscountApplied` は副作用の無い純関数。何回呼んでも同じ結果 |
| 並行性 | 非該当 | 共有状態への書き込みが無い。レンダリング時の読み取り専用計算 |
| 障害時 | 非該当 | API 呼び出しの失敗処理（`client.ts:20-22`）に変更なし。ただし「API の値を信頼しなくなった」という設計変更の影響は指摘 3 に含む |
| トランザクション境界 | 非該当 | DB 更新を含まない |
| N+1 | 非該当 | ORM クエリを含まない。`orders.service.ts` の `include: { user: true }` は差分外かつ既に 1 クエリ |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| **重大** | `apps/web/src/features/orders/orderTotal.ts:12` | 会員条件（`isMember`）が判定から落ちており、**非会員の 1000 円以上の注文に「割引」バッジが誤表示される**。しかも `OrderView` に会員フラグが無いため、この判定は web 側では原理的に正しく再現できない | API の権威ロジックは `applyDiscount(order.unitPrice * order.quantity, order.user.isMember)`（`apps/api/src/orders/orders.service.ts:19`）で、`discount.ts:10-15` が `!isMember` と `price < 1000` の**両方**で割引を見送る。新実装は後者しか見ていない。`OrderResponseDto` のフィールドは id / productName / unitPrice / quantity / status / discountedTotal のみで会員情報を含まない。結果、非会員が 1200 円×1 を注文すると API は `discountedTotal: 1200` を返すのに `isDiscountApplied` は `true` を返し、`OrderList.tsx:56-60` で「1200 円」と「割引」バッジが並んで表示される（画面上で自己矛盾する） |
| **重大** | `apps/web/src/features/orders/orderTotal.test.ts:28-39` | 既存 2 ケースは**変更前後どちらの実装でも通る**ため、上の欠陥をテストが検出しない。「非会員かつ 1000 円以上」のケースが 1 件も無い | 手計算で確認（テスト実行は権限拒否されたため未実測）：ケース 1 は 1200×1 → 旧 `1080 < 1200` = true / 新 `1200 >= 1000` = true。ケース 2 は 300×2 → 旧 `600 < 600` = false / 新 `600 >= 1000` = false。両方一致する。`makeOrder` の既定値も会員相当（`discountedTotal: 1080`）だけで、非会員相当の固定値（`discountedTotal === unitPrice * quantity` かつ 1000 円以上）を作るヘルパが無い |
| **中** | `apps/web/src/features/orders/orderTotal.ts:12` | 割引の適用条件が `apps/api/src/discount/discount.ts` と web の 2 か所に重複した。API 側の条件（率・閾値の使い方・端数処理）を変えても web は追従しない | 変更前の `order.discountedTotal < order.unitPrice * order.quantity` は API の計算結果からの派生で、判定ロジックの持ち主は API 1 か所だった。かつこの派生は正確で、`price >= 1000` なら割引額は必ず 100 円以上（`Math.floor(price * 0.9) <= price - 100`）なので「割引後合計が減っている ⟺ 会員かつ閾値以上」が成立する。定数を `@repo/shared` から import しても共有されるのは数値だけで、**条件式そのものは共有されない** |
| **中** | `apps/web/src/features/orders/orderTotal.ts:12` | 境界値テストの欠落。`>=` と `<` の反転や off-by-one を固定するテストが無い | 新たに閾値比較が web 側のロジックになったので、1000（ちょうど・true）/ 999（直下・false）/ 1001（直上・true）が必要。API 側には `discount.spec.ts:11,15,19` で 3 点揃っているのに、同じ条件を持ち込んだ web 側には無い |

**推奨**: この変更は差し戻し（`discountedTotal < unitPrice * quantity` に戻す）が最も安全。web 側で判定し続けるなら `OrderResponseDto` に割引適用フラグ（例 `isDiscountApplied: boolean`）を API が返す形にして、条件判定を API の 1 か所に戻すべき。

---

なお、このリポジトリの検証手順に従い、`case.patch` の書き換えや `expect.yml` の `claimed_layer` の変更は行っていない。上記はレビュー結果のみ。
