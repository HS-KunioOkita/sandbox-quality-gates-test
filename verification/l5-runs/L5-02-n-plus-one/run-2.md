`feat/phase5-l5-ai-review...HEAD` の差分は 1 ファイル 7 行追加 / 2 行削除。`OrdersService.findByUser` が `include: { user: true }` をやめ、注文ごとに `user` を個別取得するループに置き換わっている。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **非該当** | 差分は閾値ロジックに触れていない（`applyDiscount` の 1000 円判定は変更なし）。`orders` が 0 件のときループが 1 度も回らず `[]` を返す挙動も変更前と一致。 |
| 異常系 | **該当** | `findUniqueOrThrow`（`orders.service.ts:36`）が新たな例外経路を作っている。下表 #3。 |
| 権限 | **非該当** | `where: { userId }` は維持されており他ユーザーの注文は取得できない。Controller には `@UseGuards(AuthGuard)`（`orders.controller.ts:9`）があり、`request.userId` を渡す経路も変わっていない。 |
| 冪等性 | **非該当** | 読み取り専用（GET）で副作用がない。2 回呼んでも状態は変化しない。 |
| 並行性 | **該当** | 単一クエリが複数クエリに分割され、読み取りの一貫性が失われた。下表 #2。 |
| 障害時 | **該当** | DB 往復が 1 回から N+1 回に増え、しかも逐次 await。1 回でもタイムアウト／接続枯渇すれば一覧取得全体が失敗する。下表 #1 に含める。 |
| トランザクション境界 | **該当** | 複数テーブル更新はないが、**複数の読み取りが原子的でない**。`$transaction` にも包まれていない。下表 #2。 |
| N+1 | **該当** | 差分の中心。下表 #1。 |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| Critical | `apps/api/src/orders/orders.service.ts:35-38` | 典型的な N+1。注文 N 件に対して `user` の SELECT が N 回発行される。さらに `findMany` は `where: { userId }` で絞っているため、**全ての `order.userId` は引数の `userId` と同一**であり、まったく同じ 1 行を N 回引いている。純粋な無駄で、注文件数に比例して往復が増える。`include: { user: true }` に戻すのが正しい（それが変更前の実装）。どうしても分けるならループ外で `user` を 1 回だけ取得すれば足りる。 | `orders.service.ts:29-32` で `include` が削除され、`:36` の `findUniqueOrThrow` がループ内にある。逐次 `await` なので並列化もされていない。 |
| High | `apps/api/src/orders/orders.service.ts:29-38` | 読み取りの一貫性が壊れた。`findMany` と N 回の `user` 取得が別トランザクションのため、その間に `user.isMember` が更新されると、**同一レスポンス内の注文ごとに割引の有無が食い違う**（前半の注文は会員価格、後半は非会員価格）。変更前は単一クエリだったのでこの不整合は原理的に起きなかった。 | `toOrderResponse`（`:19`）が `order.user.isMember` で割引を分岐しており、`user` の取得タイミングが注文ごとにずれる。 |
| Medium | `apps/api/src/orders/orders.service.ts:36` | `findUniqueOrThrow` の例外が未処理。FK 制約があるため通常はユーザーが存在するが、`findMany` 実行後にユーザーが削除されると `P2025` が投げられ、捕捉されないまま 500 になる。同じサービスの `create`（`:84`）は `P2003` を `BadRequestException` に変換しているのに、ここだけ素通しで一貫していない。そもそも `include` に戻せばこの経路自体が消える。 | `:80-88` の catch は `create` にのみ存在し、`findByUser` には例外ハンドリングがない。 |
| Low | `apps/api/src/orders/orders.service.ts:34` | `const withUser = []` に型注釈がなく、暗黙の evolving `any[]` になっている。`toOrderResponse` は `OrderWithUser`（`:9`）を要求するが、push する形が要求と食い違ってもコンパイル時に検出されにくい。`const withUser: OrderWithUser[] = []` と明示すべき。 | `:40` で `withUser.map(toOrderResponse)` を呼んでおり、要素型の保証が推論任せになっている。 |

**推奨**: この差分は元の `include: { user: true }` に戻すのが最も単純な修正で、#1〜#4 の 4 件すべてが同時に解消する。ループに置き換える動機が差分から読み取れない。
