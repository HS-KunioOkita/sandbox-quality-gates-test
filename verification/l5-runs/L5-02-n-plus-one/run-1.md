## 差分の概要

`feat/phase5-l5-ai-review...HEAD`（1 ファイル / +7 -2）。`OrdersService.findByUser` の `include: { user: true }` を削除し、注文ごとに `prisma.user.findUniqueOrThrow` をループで発行する形に変更している。

## チェックリスト判定

| 項目 | 判定 | 理由 |
|---|---|---|
| 境界値 | 非該当 | 差分は割引閾値（`applyDiscount`）のロジックに触れていない。件数 0 件はループを回らず既存の空配列テストで担保されている。 |
| 異常系 | **該当** | `findUniqueOrThrow` が投げる `P2025` が未処理（下表 #2）。 |
| 権限 | 非該当 | `OrdersController` に `@UseGuards(AuthGuard)`（`orders.controller.ts:9`）。`findByUser` は `request.userId` 由来の値で `where: { userId }` を維持しており、絞り込みは緩んでいない。 |
| 冪等性 | 非該当 | GET 系の読み取りのみ。副作用なし。 |
| 並行性 | **該当（低）** | ループ実行中のユーザー削除で途中から例外化（#2 と同根）。 |
| 障害時 | **該当（低）** | DB 往復が 1 回から N+1 回に増え、逐次 await のため合計レイテンシとタイムアウト面積が件数に比例する。 |
| トランザクション境界 | **該当（低）** | `findMany` と N 回の `findUnique` が別トランザクション。読み取りスナップショットが原子的でない。 |
| N+1 | **該当（高）** | 下表 #1。本差分が作り込んでいる中心的な欠陥。 |

## 指摘

| 重大度 | ファイル:行 | 指摘 | 根拠 |
|---|---|---|---|
| 高 | `apps/api/src/orders/orders.service.ts:34-38` | N+1 クエリ。注文 1 件ごとに `user` を追加取得しており、クエリ数が件数に比例する（1 → N+1）。しかも `where: { userId }` で絞り込んでいる以上、取得される全注文の `order.userId` は引数の `userId` と同一で、**N 回とも完全に同じ 1 行を引いている**。さらに `for` + `await` の逐次実行なので往復が直列に積み上がる。変更前の `include: { user: true }` に戻すのが正しい（どうしても分離するなら `userId` で 1 回だけ引いて使い回す）。 | `orderBy` の直前にあった `include: { user: true }` が削除され、代わりにループ内 `prisma.user.findUniqueOrThrow` が追加された。`findMany` の `where` 句が `{ userId }` のままであることから、N 件の lookup が同一キーであることが差分から確定できる。 |
| 中 | `apps/api/src/orders/orders.service.ts:36` | `findUniqueOrThrow` の `P2025`（該当行なし）が未処理で、そのまま 500 になる。変更前は join なので user 行が消えていても一覧取得自体は例外にならなかった。同ファイルの `create` は `P2003` を `BadRequestException` に変換しており（`:84-86`）、Prisma 例外の扱いが非対称。`findUnique` + null チェック、あるいは変更前の join に戻すべき。 | `create` の既存コメント「未処理のままだと 500 になり、クライアントの誤りがサーバの障害として記録される」と同じ問題を、読み取り経路に新設している。 |
| 中 | `apps/api/src/orders/orders.service.spec.ts:5-14, 91-101` | この差分は既存の単体テストと矛盾しており、そのままでは赤くなる。(a) モック `MockPrisma` に `user` プロパティが無いため `this.prisma.user.findUniqueOrThrow` が `TypeError` になり、注文を 1 件以上返す 3 ケース（`:29` / `:56` / `:73`）が落ちる。(b) `:91` の「指定ユーザーで絞り込み、user を同時に取得する（**N+1 を避ける**）」は `include: { user: true }` を引数として明示的に固定しており、この変更を検出するために書かれたテストである。テストを差分に合わせて書き換えるのではなく、実装を戻すべき。 | テスト名がこの変更をそのまま禁止事項として記述している。 |
| 低 | `apps/api/src/orders/orders.service.ts:29-38` | 一覧取得と user 取得が別トランザクションのため、ループ中に user の `isMember` が更新されると、同一レスポンス内の注文間で異なる会員状態が割引計算に使われうる（`toOrderResponse` は `order.user.isMember` を参照）。join なら 1 スナップショットで一貫する。 | `applyDiscount(..., order.user.isMember)`（`:19`）。 |

## 総評

**CHANGES REQUESTED。** 変更前の `include: { user: true }` に戻すのが唯一の妥当な修正で、この差分に取り込むべき利点は見当たらない（分離クエリにする動機がコード上にもコメントにも無い）。戻せば #1・#2・#4 と、既存テストとの矛盾 #3 が同時に解消する。
