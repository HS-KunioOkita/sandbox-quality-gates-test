`feat/phase5-l5-ai-review...HEAD` の差分は 1 ファイル 1 メソッドのみ（`apps/api/src/orders/orders.service.ts` の `findByUser`）。`include: { user: true }` の JOIN を、注文ごとの `user.findUniqueOrThrow` ループに置き換えている。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | 非該当 | 差分に閾値がない。件数 0 のときはループが回らず `[]` を返すのみで、置換前と同じ。 |
| 異常系 | 一部該当 | `findUniqueOrThrow` を採用したことで、置換前には存在しなかった throw 経路（Prisma `P2025`）が増えている。FK 制約がある以上ほぼ起きないが、ハンドリングは無く 500 に化ける。下表 #3。 |
| 権限 | 非該当 | `OrdersController` に `@UseGuards(AuthGuard)` があり（`orders.controller.ts:9`）、`findByUser` には `request.userId` が渡る。差分は `where: { userId }` の絞り込みを維持しており、権限境界は変えていない。 |
| 冪等性 | 非該当 | 読み取り専用。副作用がないので 2 回呼んでも状態は変わらない。 |
| 並行性 | 該当 | 単一クエリだった読み取りが N+1 本の独立クエリに分かれ、読み取りの一貫性が失われた。下表 #2。 |
| 障害時 | 該当 | 直列 await のため DB 往復が件数に比例し、レイテンシと接続占有時間が線形に伸びる。下表 #1 の帰結。 |
| トランザクション境界 | 該当 | 複数クエリがトランザクションで括られていない（#2 と同根）。 |
| N+1 | **該当（本命）** | 下表 #1。 |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| High | `apps/api/src/orders/orders.service.ts:34-38` | 典型的な N+1。注文 1 件につき `user.findUniqueOrThrow` を 1 回、直列で発行する。クエリ数が注文件数に比例する（1 + N） | 置換前は `include: { user: true }` で 1 クエリだった。`for` ループ内で `await` しているため並列化もされておらず、往復回数だけでなく所要時間も件数に線形比例する |
| High | `apps/api/src/orders/orders.service.ts:36` | **引いているユーザーは全件同一。** `where: { userId }` で絞り込んだ結果に対して `order.userId` で引いているので、N 回とも同じ 1 行を取得している。N-1 回は完全に無駄 | `findByUser(userId)` → `findMany({ where: { userId } })` なので、`orders` の全要素で `order.userId === userId` が成り立つ |
| Medium | `apps/api/src/orders/orders.service.ts:34-38` | 注文一覧とユーザーが別トランザクションで読まれるため、ループ実行中に `user.isMember` が更新されると、同一レスポンス内で会員割引が適用された注文とされていない注文が混在しうる | `applyDiscount(..., order.user.isMember)`（:19）が注文ごとに別スナップショットの `isMember` を見る。置換前は 1 クエリなので原理的に起きなかった |
| Low | `apps/api/src/orders/orders.service.ts:36` | `findUniqueOrThrow` の `P2025` が未処理。FK があるため通常は起きないが、ユーザー削除と同時実行した場合に 404 相当が 500 になる | 同ファイル `create`（:84）では `P2003` を `BadRequestException` に変換しており、例外方針が不揃い |

**推奨修正**: `include: { user: true }` に戻す。どうしても分離するなら、ループを外に出して `user` を 1 回だけ引く（`const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } })`）ことで #1・#2・#3 が同時に解消する。

---

補足として、このリポジトリの文脈では上記が `L5-02-n-plus-one` の意図的欠陥そのものに見える。`expect.yml` の判定に使うなら「差分から N+1 を検出できた」という結果として扱えるが、`claimed_layer` は書き換えないこと。
