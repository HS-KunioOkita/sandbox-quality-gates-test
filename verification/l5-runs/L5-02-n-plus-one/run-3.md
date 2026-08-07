`git diff feat/phase5-l5-ai-review...HEAD` の差分（`apps/api/src/orders/orders.service.ts` のみ、+7/-2）をレビューしました。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | 非該当 | 差分は割引閾値ロジック（`applyDiscount`）に触れていない。取得経路のみの変更 |
| 異常系 | **該当** | `findUniqueOrThrow` が新たな例外経路を作った（下表 #3）。加えて `withUser` の型消失で `user` 欠落をコンパイラが検出できない（#4） |
| 権限 | 非該当 | `OrdersController` に `@UseGuards(AuthGuard)` があり、`findByUser(request.userId)` で認証済み ID を渡す。差分は `where: { userId }` を変えていないので認可境界に影響なし |
| 冪等性 | 非該当 | GET / 読み取り専用。副作用なし |
| 並行性 | **該当** | `findMany` と N 回の `findUnique` が別トランザクション（#3, #5） |
| 障害時 | **該当** | ループ途中の 1 件失敗で一覧全体が 500 になる（#3） |
| トランザクション境界 | **該当** | 複数テーブル更新はないが、読み取りが原子的でなく一貫性のないスナップショットを返しうる（#5） |
| N+1 | **該当** | 本差分そのものが N+1 の導入（#1） |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| 高 | `apps/api/src/orders/orders.service.ts:34-38` | `include: { user: true }` を外してループ内で `user.findUniqueOrThrow` を発行しており、クエリ数が 1 本から 1+N 本に増える。**しかも `where: { userId }` で絞っている以上、取得される全注文の `order.userId` は引数の `userId` と同一で、同じユーザーを N 回引いている**。N+1 ですらなく純粋な重複クエリ | 注文 100 件で 101 往復。JOIN 1 本に戻すのが正しく、仮に分離するとしても引くべきユーザーは 1 人なのでループの外で 1 回引けば足りる |
| 高 | `apps/api/src/orders/orders.service.spec.ts:12-14` | 既存の単体テストが実行時に落ちる。`createMockPrisma()` が返すのは `{ order: { findMany, create } }` だけで `user` キーが無く、`this.prisma.user.findUniqueOrThrow` が `TypeError: Cannot read properties of undefined` になる | `findByUser` の 3 テストすべてが該当。`MockPrisma` インタフェースにも `user` が無い。※このリポジトリの権限設定によりテスト実行コマンドが承認待ちで実行できず、コード読解ベースの判定 |
| 中 | `apps/api/src/orders/orders.service.ts:36` | `findUniqueOrThrow` は該当なしで `P2025` を投げる。従来の `include` はリレーション JOIN なのでこの失敗経路自体が存在しなかった。ユーザー削除と一覧取得が競合すると、注文一覧 API 全体が 500 で落ちる（`create` の `P2003` のようなハンドリングも無い） | `create` では同種の Prisma エラーを `BadRequestException` に変換している（`:84-86`）のに、新規経路は未処理 |
| 中 | `apps/api/src/orders/orders.service.ts:34` | `const withUser = []` は evolving array として暗黙 `any[]` に推論される。`toOrderResponse(order: OrderWithUser)` の引数型検査が実質無効化され、`user` が欠けたオブジェクトを渡してもコンパイルが通る | 上の #2（テストが壊れる欠陥）を型検査が素通しする直接の原因。`OrderWithUser[]` を明示すべき |
| 低 | `apps/api/src/orders/orders.service.ts:29-38` | `findMany` と N 回の `findUnique` が別トランザクションで、読み取り中に `user.isMember` が更新されると同一ユーザーの注文なのに割引適用が混在しうる | `discountedTotal` が注文ごとに 1080 と 1200 のように食い違う。JOIN 1 本なら構造的に起きない |

## 補足

`git log` を見るかぎりこの差分は L5-02 検証ケースの意図的な欠陥注入です。上記は「AI レビュー層（L5）がこの欠陥を捕まえるか」の実測として読んでください。**#1（N+1）に加えて #2 を検出した点が重要**で、ケースが名指ししていない `l3-test` も同時に赤くなるはずです（CLAUDE.md の「ある層を足す作業が、別の層のゲートを赤くする」と同型の、ケースが 2 層に同時に当たるパターン。§1.41 の `L3-03` と同じ構図）。`expect.yml` の `l3-test` が pass になっているなら実測と食い違うので確認が必要です。
