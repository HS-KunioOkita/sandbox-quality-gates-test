`feat/phase5-l5-ai-review...HEAD` の差分は 1 コミット・1 ファイルでした。

```
apps/api/src/orders/orders.service.ts | 9 +++++++--
```

`findByUser` が `include: { user: true }` をやめ、注文ごとに `user.findUniqueOrThrow` を await ループで呼ぶ形に変わっています。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | **非該当** | 差分は閾値ロジック（`applyDiscount`）に触れていない。閾値ちょうど / すぐ下 / すぐ上は `discount.spec.ts:10-20` で既にカバー済み（`MEMBER_DISCOUNT_MIN_PRICE` = 1000）。 |
| 異常系 | **該当** | `findUniqueOrThrow` は行が無いと throw する。従来の必須リレーション `include` では起こり得なかった失敗経路が増えた（下表 #3）。 |
| 権限 | **非該当** | `OrdersController` はクラスレベルで `@UseGuards(AuthGuard)`（`orders.controller.ts:9-10`）。`findMany` の `where: { userId }` も残っており、追加クエリのキーも `order.userId` なので他ユーザーの注文は取得できない。差分による劣化なし。 |
| 冪等性 | **非該当** | 読み取り専用（GET `/orders`）。状態変更がないため 2 回送っても差はない。 |
| 並行性 | **該当** | 2 段読み取りが原子的でないため、間に user が更新されると同一レスポンス内で `isMember` が混ざる（下表 #4）。 |
| 障害時 | **該当（軽度）** | 1 リクエストが DB へ 1+N 往復するようになり、コネクションプール占有時間と DB タイムアウトへの露出が件数に比例して増える。タイムアウト・リトライの手当ては無い（#1 に含めて記載）。 |
| トランザクション境界 | **該当（読み取り整合性）** | 複数テーブル**書き込み**は無いので古典的な原子性の論点は非該当。ただし `order.findMany` と N 回の `user.findUnique` が `$transaction` で囲まれていないため、読み取りのスナップショット一貫性が失われた（#4）。 |
| N+1 | **該当（本差分の主要な欠陥）** | 下表 #1。 |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| 高 | `apps/api/src/orders/orders.service.ts:35-38` | 典型的な N+1。注文 1 件ごとに `user.findUniqueOrThrow` を発行するため、クエリ数が件数に比例（1+N）する。しかも `await` をループ内に置いているので**レイテンシも件数 × RTT で線形に増える**。`Promise.all` にしてもクエリ数は減らない。修正は `include: { user: true }` を戻すこと。 | `findMany` から `include: { user: true }` が削除され（:29-32）、代わりにループ内で `this.prisma.user.findUniqueOrThrow({ where: { id: order.userId } })` を呼んでいる。 |
| 高 | `apps/api/src/orders/orders.service.ts:29-38` | **追加クエリは全件が同一行を引いている。** `findMany` は `where: { userId }` で絞っているので全 `order.userId` は引数の `userId` と一致する。つまり N 回のクエリは同じ user を N 回取り直しているだけで、1 件でも取れば足りる（本来は 0 件で足りる）。純粋な冗長クエリであり、性能以外の利点が一切ない。 | :30 の `where: { userId }` と :36 の `where: { id: order.userId }`。 |
| 高 | `apps/api/src/orders/orders.service.ts:29-38` | 既存ユニットテストと矛盾する。① `orders.service.spec.ts:85-96` は `findMany` が `include: { user: true }` 付きで呼ばれることを assert しており（テスト名も「N+1 を避ける」）、この差分で必ず失敗する。② `createMockPrisma()` は `{ order: { findMany, create } }` しか返さないため `this.prisma.user` が `undefined` になり、`findMany` が空でない 3 テスト（:29 / :57 / :74）は TypeError で落ちる。実装だけを変えてテストを更新していない。 | `orders.service.spec.ts:6-14`（モック定義）と :85-96（`include` の assert）を差分後のコードと突き合わせた読み取り。テストコマンドは承認が下りなかったため未実行。 |
| 中 | `apps/api/src/orders/orders.service.ts:36` | `findUniqueOrThrow` は行が無いと `PrismaClientKnownRequestError`(P2025) を throw する。ハンドリングが無いので 500 になる。`findMany` の後・このクエリの前にユーザーが削除されれば、**一覧取得 API が丸ごと 500 に倒れる**。従来の `include` は必須リレーションの JOIN なのでこの失敗経路自体が存在しなかった。同ファイルの `create` は P2003 を `BadRequestException` に翻訳しており（:80-88）、その方針とも一貫していない。 | :36 の `findUniqueOrThrow` と、:80-88 の既存の例外翻訳。 |
| 中 | `apps/api/src/orders/orders.service.ts:29-38` | 読み取りが原子的でない。`$transaction` に入っていないため、ループ実行中に `user.isMember` が変更されると、**同一レスポンス内で割引適用済みの行と未適用の行が混在する**（1 件目は会員価格、5 件目は非会員価格）。従来は単一クエリだったのでこの不整合は起こり得なかった。 | :29 の `findMany` と :36 の `findUnique` が別トランザクション。`toOrderResponse`(:19) が行ごとに `order.user.isMember` を読む。 |
| 低 | `apps/api/src/orders/orders.service.ts:34` | `const withUser = []` に型注釈が無く、ファイル冒頭で定義した `OrderWithUser`(:9) の型契約が `toOrderResponse` への入力から外れる。`Prisma.OrderGetPayload` で保証していた形が、以後 push した値の推論に委ねられる。`l1-typecheck` は通る見込みだが、`toOrderResponse` が要求する形の保証を失っている点は差分による後退。 | :9 の `OrderWithUser` 定義と :34 の無注釈 `[]`、:40 の `withUser.map(toOrderResponse)`。 |

## 補足

この差分は `verify/l5-L5-02-n-plus-one` ブランチの内容で、コミットメッセージ（`verify: L5-02-n-plus-one`）とブランチ名から、検証ケース `L5-02-n-plus-one` が意図的に注入した欠陥パッチです。上記の指摘は「直すべきバグ」としてではなく、**このレビューが N+1 を捕まえたかどうかの実測結果**として読むのが正しいと考えます。`case.patch` を書き換えないこと・`claimed_layer` を変えないことは CLAUDE.md の禁止事項なので、修正提案の適用はしていません。

なお `expect` の観点では、この欠陥は L5（AI レビュー）以外にも `l3-test`（上記 #3 のユニットテスト 4 件が落ちる）に同時に当たります。`L3-03` や `L1-01` と同じ「1 ケースが複数層に当たる」パターン（`phase0-findings.md` §1.41 と同型）なので、`expect.yml` 側でその前提が取れているか確認する価値があります。
