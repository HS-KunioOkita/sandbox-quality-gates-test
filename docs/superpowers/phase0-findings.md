# Phase 0 で得られた発見と後続フェーズへの申し送り

**対象**: `docs/多層品質ゲート_L1-L5_導入手順_NestJS-React.md`（以下「手順書」）
**設計**: `docs/superpowers/specs/2026-07-29-multilayer-quality-gates-verification-design.md`
**記録日**: 2026-07-29（Phase 0 完了時点）

Phase 0（モノレポ基盤とサンプルアプリ）の構築中に判明した事実を、手順書への修正提案候補と後続フェーズへの申し送りに分けて記録する。Phase 6 の検証レポートはこの文書を原資とする。

---

## 1. 手順書への修正提案候補

Phase 6 の検証レポートに載せる項目。**Phase 0 の時点で既に実測できたもの**に限る。

### 1.1 Prisma の postinstall は pnpm workspace でスキーマを発見できない（仮説 2 の更新）

設計書 §7 の仮説 2 は「`pnpm install --ignore-scripts` は Prisma の `prisma generate` を止めるため、明示的な生成ステップが必要」としていた。**実測はこれより深刻だった。**

`--ignore-scripts` を付けなくても壊れる。`@prisma/client` の postinstall はモノレポルートから実行されるため `apps/api/prisma/schema.prisma` を発見できず、Prisma 自身が次の警告を出してモデル型を持たないスタブ Client を生成する。

```
prisma:warn We could not find your Prisma schema in the default locations
If you have a Prisma schema file in a custom path, you will need to run
`prisma generate --schema=./path/to/your/schema.prisma` to generate Prisma Client.
```

この状態で `tsc` を回すと次で落ちる。

```
error TS2694: Namespace '...prisma/client/default".Prisma' has no exported member 'OrderGetPayload'
```

**Phase 0 での対処**：`turbo.json` に `generate` タスクを追加し、`build` / `typecheck` / `test` が `dependsOn: ["^build", "generate"]` で依存する形にした。`apps/api` の `generate` スクリプトは `prisma generate`。これは手順書 §1.2 の `turbo.json` からの意図的な逸脱である。

**手順書への提案**：§3.3 に Prisma を使う場合の明示的な生成手順を追記する。`--ignore-scripts` の有無に関わらず必要であることを明記する。

### 1.2 `void` を付けた floating promise は `no-floating-promises` を通過する

手順書 §2.4 は `@typescript-eslint/no-floating-promises: 'error'` を「NestJS で特に重要」として推奨している。しかし **`void` 演算子を付けた明示的な破棄はこのルールを通過する**。

Phase 0 では `apps/api/src/main.ts` の `void bootstrap()` がこれに該当した。起動時に `NestFactory.create` や `app.listen` が reject してもエラーが表示されず、`--unhandled-rejections=warn` を設定した環境ではサーバが立たないまま プロセスが生き残る。**L1 のゲートでは検出できない。**

同じ形が `apps/api/prisma/seed.ts` の `void prisma.$disconnect()` にもあった。

**Phase 0 での対処**：両方とも `.catch(...)` / `await` に修正した。

**手順書への提案**：§10 の落とし穴表に「`void` を付けて lint を通しながらエラーを飲み込む」を追加する。機械検出したいなら `@typescript-eslint/no-meaningless-void-operator` や、`void` の使用自体を禁止するカスタムルールを検討する。

### 1.3 pnpm 11 は postinstall スクリプトを既定でブロックする

手順書 §3.3 は `pnpm install --frozen-lockfile --ignore-scripts` を推奨しているが、pnpm 11 では **`--ignore-scripts` を付けなくてもネイティブビルドがブロックされ、`ERR_PNPM_IGNORED_BUILDS` で install が止まる**。`pnpm-workspace.yaml` に `allowBuilds` の明示が必要だった。

Phase 0 で必要だったエントリは 4 つ。

| パッケージ | 理由 |
|---|---|
| `@prisma/engines` | クエリエンジンのバイナリ取得 |
| `prisma` / `@prisma/client` | Prisma の生成フック |
| `unrs-resolver` | Jest 30 の `jest-resolve` が使うネイティブリゾルバ |

**手順書への提案**：§3.3 に pnpm 10 以降の build 承認ゲートについて触れる。`--ignore-scripts` を CI で使う方針と、ローカル開発で `allowBuilds` が必要になる点は別問題として整理する。

### 1.4 TypeScript のバージョン上限が存在する

手順書は TypeScript のバージョンに触れていないが、**最新版は使えない**。

| 制約元 | peerDependency |
|---|---|
| `ts-jest@29.4.12` | `typescript: ">=4.3 <7"` |
| `typescript-eslint@8.65.0` | `typescript: ">=4.8.4 <6.1.0"` |

交差は上限 6.0.x。Phase 0 では実績を優先して **5.9.3** に固定した（最新は 7.0.2）。

**手順書への提案**：§2 に、L1（`typescript-eslint`）と L3（`ts-jest`）が TypeScript のバージョン上限を課すことを明記する。

### 1.5 Prisma 7 は生成物をリポジトリ内に出力する

Prisma 7 の `prisma-client` ジェネレータは **生成物を TypeScript ソースとして `output` 指定のパスに出力する**。手順書 §5.2 は「生成コードを Stryker の `mutate` から除外せよ」と書いているが、Prisma 7 の場合は L1（`tsc --noEmit` と ESLint）の対象にもなる。手順書はこの点に触れていない。

Phase 0 では検証ノイズを避けるため Prisma 6.19.3（`prisma-client-js`、出力先は `node_modules/.prisma/client`）を採用した。

**手順書への提案**：§2.6 または §5.2 に、リポジトリ内に生成コードを出すツールを使う場合は L1 側の除外も必要であることを追記する。

### 1.6 `turbo.json` の `test` の `outputs` は実際の出力と一致しない

手順書 §1.2 の `turbo.json` は `"test": { "dependsOn": ["^build"], "outputs": ["coverage/**"] }` としているが、§4.6 の実行コマンドは `pnpm turbo test` でカバレッジを取らない。結果、turbo が `no output files found for task api#test` を警告し、`test` タスクのキャッシュが機能しない。

**手順書への提案**：カバレッジを常時取る（`--coverage` を付ける）か、`outputs` を外すか、どちらかに揃える。

### 1.7 手順書 §2.4 は ESLint 設定ファイルを 2 つ書き漏らしている（仮説 6 の結論）

手順書 §2.4 は `packages/eslint-config/index.js` と `apps/web/eslint.config.js` しか示していない。ESLint 10 は lint 対象ファイルから上方向に設定ファイルを探索し、**見つかった設定で上位の設定を置き換える（マージしない）**。実測で確認した。

そのため `pnpm eslint .` をルートで成立させるには次の 2 つが追加で必要だった。

- ワークスペースルートの設定 — `packages/shared` などパッケージ固有設定を持たない場所を担当する。無いと設定ファイル未検出で失敗する
- `apps/api` の設定 — NestJS 固有設定を当てる

さらに、**ファイル名を `eslint.config.js` にできるのはそのパッケージが `"type": "module"` のときだけ**である。`apps/web`（Vite、`type: module`）では動くが、`apps/api`（NestJS、CommonJS）とルートでは ESM 構文が落ちるため `eslint.config.mjs` にする必要がある。手順書はこの点に触れていない。

### 1.8 `no-unused-disable` は非推奨かつ no-op（仮説 7 の結論）

設計書 §7 の仮説 7 は「`reportUnusedDisableDirectives` と `eslint-comments/no-unused-disable` は機能重複し二重報告になる」としていたが、**実測では二重報告は起きなかった**。実際の問題は別だった。

| 設定 | 重大度 | `--max-warnings=0` あり | なし |
|---|---|---|---|
| 何も設定しない（ESLint 10 の既定） | warn | exit 1 | exit 0 |
| プラグインの `no-unused-disable` のみ | warn（既定と同一出力） | exit 1 | exit 0 |
| `linterOptions.reportUnusedDisableDirectives: 'error'` | error | exit 1 | exit 1 |

プラグインルールは既定と同じ warn しか出さず**何も追加していない（no-op）**。加えて `no-unused-disable` は **4.7.0 で deprecated、5.0.0 で削除予定**であり、非推奨メッセージ自体が「ESLint 組み込みの `linterOptions` を使え」と指示している。

**手順書への提案**：§2.4 のルール一覧から `no-unused-disable` を削除する。`linterOptions.reportUnusedDisableDirectives: 'error'` は残す（ESLint 10 の既定は `warn` なので、`--max-warnings=0` を付けない実行では見逃すため意味がある）。

### 1.9 §2.4 の `no-restricted-imports` は相対パスの越境 import を検出できない（検証ケース L1-06 の結論）

Phase 1 の検証ケース 6 本のうち唯一、**手順書の主張どおりに止まらなかった**ケースである（`verification/RESULTS.md` の `L1-06-web-imports-api` 行）。

手順書 §10 は「Web から API の内部実装を直接 import する」を L1 が捕まえる落とし穴として挙げ、§2.4 は `no-restricted-imports` の `patterns` でこれを禁じる構成を示している。実測すると、この構成は相対パスでの越境 import を**まったく検出しない**。

```ts
// apps/web/src/features/orders/orderTotal.ts
import { applyDiscount } from '../../../../api/src/discount/discount';
```

このパスは `apps/api/src/discount/discount` に解決される。`patterns: [{ group: ['**/apps/api/src/**'] }]` を設定していても lint は通る。

| import の書き方 | `no-restricted-imports` |
|---|---|
| `'../../../../api/src/discount/discount'` | 発火しない |
| `'@repo/../apps/api/src/discount/discount'` | 発火する |

**原因**：`no-restricted-imports` の `patterns` は**解決後のパスではなく、ソースに書かれた import 指定子の文字列**に対する glob マッチである。相対パスの文字列には `apps/api` が現れないため、どんな `group` を書いても一致しない。

型チェックも止めない。`apps/web/tsconfig.json` の `include` は `src/**` だけだが、**`include` は起点ファイルを絞るだけで、import 経由で到達したファイルを型チェックから免除しない**。`discount.ts` 自体に型エラーが無いため `tsc` は成功する。

**手順書への提案**：§2.4 の依存境界の強制を `no-restricted-imports` に頼らない。解決後のパスで判定する `eslint-plugin-import` の `import/no-restricted-paths` に置き換えるか、併用する。`no-restricted-imports` を残す場合は「パッケージ名での import しか止められない」という限界を明記する。

---

## 2. 検証ケースの期待値に対する申し送り

Phase 0 の実装を受けて、設計書 §9 の検証ケースのうち 2 件は期待値の調整が必要。設計書本体にも同じ内容を追記済み。

### 2.1 `L3-03-authz-bypass` — 403 を返す経路が存在しない

Phase 0 の API は `GET /orders`（自分の一覧のみ）と `POST /orders` だけで、リソース単位の取得（`GET /orders/:id`）が無い。認可欠落は「403 が出ない」ではなく **「200 で他人のデータが返る」** 形で現れる。

Phase 3 で **(a)** `GET /orders/:id` を追加して所有者チェックを入れるか、**(b)** ケースの期待値を書き換えるかを選ぶ。

なお `@UseGuards` を外すと `request.userId` が実行時 `undefined` になり、Prisma が `where: { userId: undefined }` を「条件なし」と解釈して**全ユーザーの注文を返す**。型チェックでも既存の単体テストでも捕まらないため、`L2-02-guard-missing`（Semgrep カスタムルール＝仮説 5）の検証対象としては理想的な形になっている。

### 2.2 `L5-02-n-plus-one` — L3 も赤になるため「L1〜L4 全緑」を満たさない

`apps/api/src/orders/orders.service.spec.ts` が `findMany` の呼び出し形（`include: { user: true }` を含む）をアサーションで固定している。これは「N+1 の混入が L3 で捕まるのか L5 でしか捕まらないのか」を切り分けるための意図的な設計だが、その結果 `L5-02` は L3 も赤になる。

Phase 5 で L4 の 2 ケースと同じ基準を適用する。**L3 も一緒に赤になるならそのケースは L5 の価値を証明していない**ので、クエリ形の固定を外すか、ケースを別の題材に作り直す。

「単体テストがクエリ形を固定していれば N+1 は L3 で捕まる」という事実自体が、手順書 §10 の「N+1 は L5 で拾う」という割り当てへの反証データになる。

---

## 3. Phase 別の技術的申し送り

### Phase 1（L1 + 検証ハーネス）

| # | 内容 |
|---|---|
| 1 | `apps/api/prisma/seed.ts` が `console.info` / `console.error` を使う。手順書 §2.4 の `no-console: 'error'` に抵触する。`eslint.config.js` で `prisma/**` を対象外にするか、`require-description` 付きの抑制コメントを書くかを判断する |
| 2 | ルートと `apps/api` の `eslint.config.js` が手順書に無い（仮説 6）。`pnpm eslint .` をルートで回すにはルートのフラットコンフィグが必要 |
| 3 | `apps/web/tsconfig.node.json` を分けてある。`projectService: true` が `vite.config.ts` / `vitest.config.ts` を解決できるか確認する |
| 4 | `apps/api/tsconfig.spec.json` は `tsconfig.json` の `include` を継承するため、`noUnusedLocals` / `noUnusedParameters` の緩和がテストコードに限定されていない。ゲートである `pnpm turbo typecheck` は厳格な `tsconfig.json` で全ファイルを見るので抜け穴にはならないが、ESLint 側がどの tsconfig を使うかで挙動が変わる可能性がある |
| 5 | `apps/api/src/orders/orders.service.spec.ts` の `MockPrisma.findMany` は型パラメータ無しの `jest.Mock`。実 Prisma の型と突き合わされない |

### Phase 2（L2）

| # | 内容 |
|---|---|
| 6 | `OrdersController` のデコレータ順は `@Controller('orders')` → `@UseGuards(AuthGuard)`。手順書 §3.2 の Semgrep カスタムルールは逆順しか `pattern-not` で除外しないため、偽陽性が出るかの検証対象（仮説 5）。**変更しないこと** |
| 7 | `pnpm-workspace.yaml` の `'@prisma/client': true` は `generate` の turbo 配線後は不要。その postinstall はスキーマを発見できずスタブを作るだけ。`--ignore-scripts` の検証と併せて整理する |
| 8 | `prisma generate` が `DATABASE_URL` 未設定の環境でどう振る舞うか未確認。cloudbuild 相当を組むときに env の受け渡しを意識する |

### Phase 3（L3）

| # | 内容 |
|---|---|
| 9 | `AuthGuard` の単体テストが無い。e2e で 401 / 403 をカバーする |
| 10 | `apps/web/src/api/client.ts` の `(await response.json()) as OrderView[]` は無検証キャスト。`openapi-typescript` の生成型に差し替える境界がここに閉じている |
| 11 | Playwright MCP が `.playwright-mcp/` を作る。`.gitignore` に追加済み |
| 12 | `OrdersService.create` は存在しないユーザー ID で FK 違反（P2003）が未処理のため 500 を返す。e2e で「不正ユーザー」を試すと 401/400 ではなく 500 になる |

### Phase 4（L4）

| # | 内容 |
|---|---|
| 13 | **`turbo` の `dependsOn` は turbo 経由でのみ効く。** 手順書 §5.3 の `scripts/stryker-diff.sh` は `pnpm --filter api exec stryker` を直叩きするため `generate` を経由しない。ゲートスクリプトは turbo 経由にするか、明示的に `generate` を先行させる必要がある |
| 14 | `toOrderResponse` は `orders.service.ts` のファイルローカル関数。`*.module.ts` でもエントリポイントでもないので `mutate` から除外しない |
| 15 | `apps/web` の Vitest は `afterEach(cleanup)` を明示登録済み。これが無いとテスト間で DOM が蓄積し、自分の render を検証しないテストが mutant を殺せなくなる（Phase 0 で実測・修正済み） |

---

## 4. Phase 0 の受け入れ確認記録

| 項目 | 結果 |
|---|---|
| `pnpm turbo build typecheck test` | 9 タスク成功、23 テスト（api 13 / web 10） |
| 白紙リビルド（全 `node_modules` / `dist` / `.turbo` 削除 → `pnpm install` → turbo） | 9/9 成功、手動介入なし |
| `GET /orders` 認証なし | HTTP 401 |
| `GET /orders` 認証あり（会員） | キーボード `discountedTotal` 1080 / ケーブル 600 |
| `POST /orders` 不正入力（`quantity: 0`） | HTTP 400 |
| `http://localhost:5173` の画面表示 | 会員は 2 件・キーボードのみ割引・合計 1680 円／非会員はモニター 1 件・割引なし・合計 5000 円（Playwright で確認） |
| `README.md` の手順が白紙から通る | 通る（`turbo` の `generate` 配線後） |
