# Phase 3: L3 ゲート（テスト層）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手順書 §4 の L3（Testcontainers 統合テスト / supertest e2e / fast-check / OpenAPI 型生成と drift 検出）をゲートとして実装し、L3 系 3 ケースの判定を完了させ、仮説 8 に結論を出す。

**Architecture:** ブロックするゲートを 2 本（`l3-test` / `l3-openapi-drift`）足して `GATE_ORDER` を 8 本にする。`l3-test` は `pnpm turbo test` を叩くだけの薄いスクリプトにし、テスト種別（unit / integration / e2e）の切り分けは Jest の `projects` に持たせる。Playwright は `l3-e2e-web.sh` として作るが `GATE_ORDER` には入れない（手順書 §4.1 の「△ 主要導線のみ」「フルは nightly」に従い、Phase 5 で回す）。ハーネス側は経過時間の計測出力を足し、非ブロックゲートの照合規約を確定させる。

**Tech Stack:** Jest 30.4.2 + ts-jest 29.4.12（既存）、`@testcontainers/postgresql` 12.0.4、supertest 7.2.2、`@nestjs/swagger` 11.4.6、`openapi-typescript` 7.13.0、fast-check 4.9.0、`@playwright/test` 1.62.0、bash、Node.js 標準テストランナー（`node --test`）

---

## 事前に確認済みの事実

計画時に実際に確認したもの。実装時に前提が崩れていたら、そのこと自体を `phase0-findings.md` に記録する。

| # | 事実 | 出典 |
|---|---|---|
| A | `apps/api/prisma/migrations/20260729042639_init/` が存在する。Testcontainers で `prisma migrate deploy` が使える（`db push` に頼らなくてよい） | `ls apps/api/prisma/migrations` |
| B | `apps/api/jest.config.ts` の `testMatch` は `<rootDir>/src/**/*.spec.ts` と `<rootDir>/test/**/*.spec.ts` のみ。**`orders.int-spec.ts` は `*.spec.ts` にマッチしない**（末尾が `-spec.ts` であって `.spec.ts` ではない）。手順書 §4.1 の命名をそのまま使うと、テストを置いても Jest が拾わず緑のままになる | `apps/api/jest.config.ts` |
| C | 手順書 §4.2 は `setup-db.ts` のコードだけを示し、**Jest への配線（`setupFilesAfterEnv` / `projects`）を書いていない**。素朴に全テストへ適用すると、DB を使わない単体テストでも毎回コンテナが立つ | 手順書 §4.2 |
| D | `PrismaService` は `PrismaClient` を継承し、コンストラクタで接続文字列を固定する。`process.env.DATABASE_URL` は**インスタンス化の時点**で読まれるので、`beforeAll` でコンテナ URL を設定したあとに `new` する必要がある | `apps/api/src/prisma/prisma.service.ts` |
| E | リポジトリルートに `.env`（`DATABASE_URL`）がある。Prisma CLI は `.env` を読むが既存の `process.env` を上書きしない。`migrate deploy` にはコンテナの URL を `env` で明示的に渡す | `.env` / Prisma の仕様 |
| F | `pnpm-workspace.yaml` に `minimumReleaseAge: 10080`（7 日）がある。公開直後の版はインストールできない。本計画のバージョンはすべて 2026-07-27 以前に公開されたものを選んである | `pnpm-workspace.yaml` |
| G | `turbo.json` の `test` は `dependsOn: ["^build", "generate"]`。`pnpm turbo test` 経由なら Prisma Client の生成が先行する。**turbo を経由しない直叩きでは生成が走らない**（申し送り #13 と同じ型） | `turbo.json` |
| H | 現在の `RESULTS.md` は 11 ケース中 ✅ 7 / ❌ 4。対照実行は緑 | `verification/RESULTS.md` |
| I | `apps/web/src/App.tsx` は**ユーザー ID を画面から手入力**する作りで、固定 ID を持たない。一方 `seed.ts` は `@default(uuid())` に任せているので投入のたびに ID が変わる。Playwright から一覧を出すには seed 側の ID を固定する必要がある | `apps/web/src/App.tsx` / `apps/api/prisma/seed.ts` |
| J | `L2-01-phantom-package` の `expect` は `l2-install: fail` の 1 行のみ。先頭ゲートが失敗すると後続は実行されないため、ゲートを増やしてもこのケースの `expect.yml` は変更不要 | `verification/cases/L2-01-phantom-package/expect.yml` |

---

## Global Constraints

すべてのタスクの受け入れ条件に、暗黙にこの節が含まれる。

- **`expect.yml` の `claimed_layer` は絶対に変えない。** 手順書 §10 の主張そのものであり、これが検証対象である。実測に合わせて書き換えると判定が恒真になる。
- **判定を `match` にするために `case.patch` を書き換えない。** `mismatch` / `not-caught` が出たらそれが成果物である。
- **`expect`（各ゲートの pass/fail）は実測に合わせて更新してよい。** 初回実行で確定させる。
- ゲートの exit code は `0`=pass / `1`=fail（欠陥を検出）/ `2`=error（ツールが実行できなかった）。**error を fail に写像しない。** これが最重要（設計書 §6.1）。
- ゲート名は必ず `lN-` で始める。`judge.mjs` の `layerOfGate` がゲート名の先頭 2 文字で層を導くため（申し送り #21）。
- ルート `eslint.config.mjs` の `ignores` に `apps/**` を足さない（申し送り #22）。
- 依存は完全固定。`^` / `~` を付けない。バージョンは本計画に書いた値をそのまま使う。
- `corepack enable` を実行しない。pnpm 11.1.1 はグローバルインストール済み。
- TypeScript は 5.9.3 に固定（ts-jest と typescript-eslint の peer 制約による上限。§1.4）。
- `scripts/gates/*.sh` と `verification/*.sh` は `shellcheck` を通す。
- **ゲートや設定を足したら、意図的に違反を 1 つ入れて赤くなることを確認する。** 緑を確認するだけでは、そのゲートが何も見ていない状態と区別できない。同じことがテストにも当てはまる（テストを足したら対象の実装を壊して赤くなることを確認する）。
- tsconfig / jest 設定に触るタスクの後は `./verification/run-case.sh L1-05-unchecked-index` を実行し、`l1-typecheck: fail` が返ることを確認する（申し送り #24。`composite` / `noEmitOnError` を入れると `tsc` の fail code が 2 から 1 に変わり、型エラーが error に化ける）。
- ケースを作ったら**コミットしてから** `run-case.sh` を実行する。`git status --porcelain` は未追跡ファイルも報告するため、作業ツリーが汚れていると exit 2 で止まる。
- `run-all.sh` は Bash ツールのタイムアウト上限（10 分）を超える。**バックグラウンドで実行する。**

---

## File Structure

### 新規作成

| パス | 責務 |
|---|---|
| `apps/api/test/setup-db.ts` | Testcontainers で PostgreSQL を起動し、マイグレーションを適用して `DATABASE_URL` を差し替える。DB を使うテストプロジェクトだけが読み込む |
| `apps/api/test/orders.int-spec.ts` | `OrdersService` を実 DB に対して検証する統合テスト |
| `apps/api/test/orders.e2e-spec.ts` | NestJS アプリを立てて supertest で HTTP 経由の振る舞いを検証する e2e テスト |
| `apps/api/src/auth/auth.guard.spec.ts` | `AuthGuard` の単体テスト（申し送り #9） |
| `apps/api/src/openapi.ts` | OpenAPI スキーマを `openapi.json` に書き出す CLI エントリ |
| `apps/web/src/api/schema.d.ts` | `openapi-typescript` の生成物。手で編集しない |
| `apps/web/playwright.config.ts` | Playwright の設定。webServer で API と Vite を起動する |
| `apps/web/e2e/orders.spec.ts` | 主要導線 1 本（注文一覧の表示） |
| `scripts/gates/l3-test.sh` | L3 ゲート本体。`pnpm turbo test` を叩き、exit code を 3 値へ写像する |
| `scripts/gates/l3-openapi-drift.sh` | OpenAPI 生成物の drift 検出ゲート |
| `scripts/gates/l3-e2e-web.sh` | Playwright ゲート。`GATE_ORDER` には入れない |
| `verification/cases/L3-01-broken-logic/` | 割引計算を壊すケース |
| `verification/cases/L3-02-openapi-drift/` | DTO を変えて生成物を更新しないケース |
| `verification/cases/L3-03-authz-bypass/` | 所有者チェックだけを外すケース |

### 変更

| パス | 変更内容 |
|---|---|
| `apps/api/jest.config.ts` | `projects` で unit / integration / e2e を分ける。`*-spec.ts` を拾えるよう `testMatch` を直す |
| `apps/api/package.json` | 依存追加と `generate:openapi` スクリプト |
| `apps/api/src/orders/orders.controller.ts` | `GET /orders/:id` を追加 |
| `apps/api/src/orders/orders.service.ts` | `findOneForUser`（所有者チェック）と `create` の FK 違反処理 |
| `apps/api/src/discount/discount.spec.ts` | fast-check のプロパティを追加 |
| `apps/api/prisma/seed.ts` | Playwright から参照できるようユーザー ID を固定 |
| `apps/web/src/api/client.ts` | 無検証キャストを生成型に差し替え（申し送り #10） |
| `apps/web/package.json` | 依存追加と `test:e2e` スクリプト |
| `scripts/gates/gates.list.sh` | `GATE_ORDER` に `l3-test` と `l3-openapi-drift` を追加 |
| `scripts/gates/gates.test.sh` | 新ゲートの exit code 契約テスト |
| `verification/run-case.sh` | ゲート別の経過秒数を記録（申し送り #26） |
| `verification/run-all.sh` | ケース別・全体の経過時間を出力 |
| `verification/cases/L1-*/expect.yml`、`L2-*/expect.yml` | 新ゲート 2 本の期待値を追記（11 ファイル） |
| `docs/superpowers/phase0-findings.md` | 仮説 8 の結論、新しい発見、Phase 4 への申し送り |
| `verification/RESULTS.md` | `run-all.sh` の生成物 |

---

## Task 1: Testcontainers 統合テスト基盤（仮説 8 に結論を出す）

**Files:**
- Create: `apps/api/test/setup-db.ts`
- Create: `apps/api/test/orders.int-spec.ts`
- Modify: `apps/api/jest.config.ts`
- Modify: `apps/api/package.json`

**Interfaces:**
- Produces: `apps/api/test/setup-db.ts` は Jest の `setupFilesAfterEnv` として読み込まれ、`beforeAll` で `process.env.DATABASE_URL` をコンテナの接続 URI に差し替える。以降のタスクの統合 / e2e テストはこれに依存する。
- Produces: `jest.config.ts` は `projects` を 3 つ（`unit` / `integration` / `e2e`）持つ。`integration` は `<rootDir>/test/**/*.int-spec.ts`、`e2e` は `<rootDir>/test/**/*.e2e-spec.ts` を拾う。

このタスクの眼目は**仮説 8 の実証**である。手順書 §4.2 のコードをそのまま置いて落ちることを実測してから直す。先に正解を書いてしまうと「手順書に記述漏れがあった」という検証結果が得られない。

- [ ] **Step 1: 依存を追加する**

```bash
pnpm add -D --filter api @testcontainers/postgresql@12.0.4
```

`minimumReleaseAge: 10080` に引っかかって拒否された場合は、`pnpm view @testcontainers/postgresql time --json` で 7 日以上前に公開された最新版を選び、その版を使う。**選び直した場合はバージョンをこの計画のコメントに残す**（後続タスクが同じ版を前提にする）。

- [ ] **Step 2: 手順書 §4.2 のコードをそのまま置く**

```ts
// apps/api/test/setup-db.ts
// 手順書 §4.2 のコードをそのまま置いている。この時点では意図的に「手順書どおり」であり、
// マイグレーションの適用が無い。仮説 8（記述漏れ）を実測するための状態。
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';

let container: StartedPostgreSqlContainer;

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16-alpine').start();
  process.env.DATABASE_URL = container.getConnectionUri();
}, 60_000);

afterAll(async () => {
  await container?.stop();
});
```

- [ ] **Step 3: 統合テストを書く**

`PrismaService` はインスタンス化の時点で `DATABASE_URL` を読む（事前確認 D）。モジュールのトップレベルで `new` せず、`beforeAll` の中で作る。

```ts
// apps/api/test/orders.int-spec.ts
import { OrdersService } from '../src/orders/orders.service';
import { PrismaService } from '../src/prisma/prisma.service';

describe('OrdersService（実 DB）', () => {
  let prisma: PrismaService;
  let service: OrdersService;

  beforeAll(async () => {
    // setup-db.ts の beforeAll が先に走り、DATABASE_URL がコンテナのものに
    // 差し替わっている。PrismaClient は new した時点の URL を掴むので、
    // ここより前にインスタンス化してはいけない。
    prisma = new PrismaService();
    await prisma.$connect();
    service = new OrdersService(prisma);
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await prisma.order.deleteMany();
    await prisma.user.deleteMany();
  });

  it('自分の注文だけを、会員割引を適用した合計付きで返す', async () => {
    const member = await prisma.user.create({
      data: { email: 'member@example.com', name: '会員', isMember: true },
    });
    const other = await prisma.user.create({
      data: { email: 'other@example.com', name: '他人', isMember: true },
    });
    await prisma.order.create({
      data: { userId: member.id, productName: 'キーボード', unitPrice: 1200, quantity: 1 },
    });
    await prisma.order.create({
      data: { userId: other.id, productName: 'マウス', unitPrice: 2000, quantity: 1 },
    });

    const orders = await service.findByUser(member.id);

    expect(orders).toHaveLength(1);
    expect(orders[0]?.productName).toBe('キーボード');
    // 1200 * 1 = 1200 は閾値 1000 以上なので 10% 引きで 1080
    expect(orders[0]?.discountedTotal).toBe(1080);
  });

  it('非会員には割引を適用しない', async () => {
    const guest = await prisma.user.create({
      data: { email: 'guest@example.com', name: '非会員', isMember: false },
    });
    await prisma.order.create({
      data: { userId: guest.id, productName: 'モニター', unitPrice: 5000, quantity: 1 },
    });

    const orders = await service.findByUser(guest.id);

    expect(orders[0]?.discountedTotal).toBe(5000);
  });
});
```

- [ ] **Step 4: Jest を projects 構成にする**

事前確認 B と C の 2 つをここで潰す。`*.int-spec.ts` は `*.spec.ts` にマッチしないので `testMatch` を分ける。DB を使わない単体テストで毎回コンテナが立たないよう、`setupFilesAfterEnv` は `integration` / `e2e` プロジェクトだけに持たせる。

```ts
// apps/api/jest.config.ts
import type { Config } from 'jest';

// 3 プロジェクトで共通の変換設定。ts-jest は tsconfig.spec.json を使う。
const common = {
  testEnvironment: 'node',
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/tsconfig.spec.json' }],
  },
  moduleFileExtensions: ['ts', 'js', 'json'],
} satisfies Partial<Config>;

const config: Config = {
  rootDir: '.',
  // 手順書 §4.1 は種別ごとにファイル名を分ける（*.int-spec.ts / *.e2e-spec.ts）。
  // ここを 1 つの testMatch で束ねると、`*.spec.ts` は `-spec.ts` 終わりの
  // ファイルにマッチしないため、統合テストと e2e が黙って実行されない。
  // 「テストを置いたのに Jest が拾わず緑のまま」は、このリポジトリが
  // 繰り返し踏んでいる「緑と守っているは別物」の型そのものである。
  projects: [
    {
      ...common,
      displayName: 'unit',
      rootDir: '.',
      testMatch: ['<rootDir>/src/**/*.spec.ts'],
    },
    {
      ...common,
      displayName: 'integration',
      rootDir: '.',
      testMatch: ['<rootDir>/test/**/*.int-spec.ts'],
      // DB を立てるのはこのプロジェクトと e2e だけ。単体テストに持たせると
      // Docker が無い環境で単体テストまで巻き添えで落ちる。
      setupFilesAfterEnv: ['<rootDir>/test/setup-db.ts'],
      testTimeout: 120_000,
    },
    {
      ...common,
      displayName: 'e2e',
      rootDir: '.',
      testMatch: ['<rootDir>/test/**/*.e2e-spec.ts'],
      setupFilesAfterEnv: ['<rootDir>/test/setup-db.ts'],
      testTimeout: 120_000,
    },
  ],
  collectCoverageFrom: ['src/**/*.ts', '!src/**/*.spec.ts', '!src/main.ts', '!src/**/*.module.ts'],
  coverageDirectory: 'coverage',
};

export default config;
```

- [ ] **Step 5: 実行して落ちることを確認する（仮説 8 の実測）**

Docker Desktop が起動していることを確認してから実行する。

```bash
pnpm --filter api exec jest --selectProjects integration
```

期待: **失敗する。** Prisma が `The table 'public.User' does not exist in the current database` の趣旨のエラーを返す。手順書 §4.2 は `DATABASE_URL` を差し替えるところまでしか書いておらず、空の DB にスキーマを作る手順が無いためである。

**出力をそのまま控えておく**（次の Step でこれを findings に引用する）。もしこの時点で成功してしまった場合は、仮説 8 が否定されたということなので、その事実と原因（例: 別経路でスキーマが作られている）を記録し、Step 6 のマイグレーション追加は行わずに Step 8 へ進む。

- [ ] **Step 6: マイグレーション適用を足す**

```ts
// apps/api/test/setup-db.ts
import { execFileSync } from 'node:child_process';
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';

let container: StartedPostgreSqlContainer;

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16-alpine').start();
  const url = container.getConnectionUri();
  process.env.DATABASE_URL = url;

  // 手順書 §4.2 に無い一手（仮説 8）。DATABASE_URL の差し替えだけでは
  // テーブルが 1 つも無い DB に接続することになる。
  //
  // env に DATABASE_URL を明示的に渡す理由: Prisma CLI はリポジトリルートの
  // .env を読むが、既に process.env にある値は上書きしない。ここで渡さないと
  // 「.env のローカル DB に向けてマイグレーションを適用してしまう」——つまり
  // テストがコンテナではなく開発用 DB を壊す事故になる。
  //
  // migrate dev ではなく deploy を使う。dev は対話的でシャドー DB を作る。
  execFileSync('pnpm', ['exec', 'prisma', 'migrate', 'deploy'], {
    cwd: `${__dirname}/..`,
    env: { ...process.env, DATABASE_URL: url },
    stdio: 'inherit',
  });
}, 120_000);

afterAll(async () => {
  await container?.stop();
});
```

タイムアウトを 60 秒から 120 秒へ広げている。コンテナ起動に加えてマイグレーション適用（初回はイメージの pull も）が入るため。

- [ ] **Step 7: 実行して通ることを確認する**

```bash
pnpm --filter api exec jest --selectProjects integration
```

期待: 2 件とも PASS。

- [ ] **Step 8: テストが実装を固定していることを確認する**

「テストを足したら、対象の実装を壊してそのテストが赤くなることを確認する」（Global Constraints）。

`apps/api/src/discount/discount.ts` の `MEMBER_DISCOUNT_RATE` の適用を一時的に外す（`return price;` を先頭に足す）。

```bash
pnpm --filter api exec jest --selectProjects integration
```

期待: 「自分の注文だけを〜」が `1080` を期待して `1200` を得て FAIL する。確認したら**変更を戻す**（`git checkout apps/api/src/discount/discount.ts`）。

- [ ] **Step 9: 単体テストが巻き添えになっていないことを確認する**

```bash
pnpm --filter api exec jest --selectProjects unit
```

期待: 既存の単体テストだけが走り、Docker コンテナは起動しない（実行時間が数秒で終わる）。`setupFilesAfterEnv` を全プロジェクトに付けてしまっていないことの確認である。

- [ ] **Step 10: 仮説 8 の結論を findings に書く**

`docs/superpowers/phase0-findings.md` の §1 に新しい項目として追記する。番号は既存の最大値（§1.28）の次を使う。

書く内容:
- 手順書 §4.2 のコードをそのまま置くと何が起きたか（Step 5 で控えたエラー出力を引用する）
- `prisma migrate deploy` を足すと通ること
- `env` に `DATABASE_URL` を明示的に渡さないと `.env` のローカル DB に適用されうること
- 手順書 §4.2 が `setup-db.ts` の Jest への配線（`projects` / `setupFilesAfterEnv`）を書いていないこと、素朴に全テストへ適用すると単体テストでも毎回コンテナが立つこと（事前確認 C）
- 手順書 §4.1 の命名（`*.int-spec.ts`）は Jest の既定の `testMatch` に載らないこと（事前確認 B）

- [ ] **Step 11: コミット**

```bash
git add apps/api/test apps/api/jest.config.ts apps/api/package.json pnpm-lock.yaml docs/superpowers/phase0-findings.md
git commit -m "feat: Testcontainers 統合テスト基盤（仮説 8 に結論）"
```

---

## Task 2: `l3-test.sh`（テストゲート）

**Files:**
- Create: `scripts/gates/l3-test.sh`
- Modify: `scripts/gates/gates.list.sh`
- Modify: `scripts/gates/gates.test.sh`

**Interfaces:**
- Consumes: Task 1 の `jest.config.ts`（projects 構成）
- Produces: `scripts/gates/l3-test.sh`。exit code は 0=pass / 1=テスト失敗 / 2=実行不能。`GATE_ORDER` の 7 番目に入る。

**このタスクが Phase 3 で最も事故りやすい。** Jest は「テストが失敗した」ときも「Docker に繋がらずコンテナが起動できなかった」ときも exit 1 を返す。素直に `gate_finish "$?" 1` と書くと、Docker Desktop が止まっているだけの状態が「L3 が欠陥を検出した」として記録される。設計書 §6.1 が「このハーネス最大の誤判定リスク」と呼ぶ形であり、Phase 2 の `l2-install.sh` で実際に踏んだ型（申し送り #16）でもある。

- [ ] **Step 1: ゲートを書く**

```bash
#!/usr/bin/env bash
# L3: テスト（手順書 §4.6）
#
# 手順書は `pnpm turbo test --filter='...[origin/main]'` と書くが、ここでは
# フィルタを外して全パッケージを走らせる。検証ハーネスは main から切った
# 検証ブランチ上で実行するので、`...[origin/main]` は「origin/main からの差分」を
# 見る。origin にまだ無いコミットとの比較になり、ケースによって走る範囲が
# 変わってしまう。何が走ったか分からないゲートでは判定に使えない。
# この差自体は手順書への注記候補として findings に残す。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm
# 統合テストと e2e は Testcontainers で PostgreSQL を立てる。Docker が無い状態で
# 走らせると Jest はテスト失敗（exit 1）として報告する。それを fail に写像すると
# 「Docker Desktop が止まっている」が「テストが欠陥を検出した」になる。
# ここで先に error(2) へ倒す。
gate_require_docker

# turbo 経由で実行する。turbo.json の test は dependsOn に generate を持つので、
# Prisma Client の生成が先行する。直叩き（pnpm --filter api exec jest）では
# 生成が走らない（申し送り #13 と同じ型）。
_test_log=$(mktemp)
pnpm turbo test 2>&1 | tee "$_test_log"
raw="${PIPESTATUS[0]}"

if [ "$raw" -eq 0 ]; then
  rm -f "$_test_log"
  exit "$GATE_PASS"
fi

# Jest はテスト失敗もコンテナ起動失敗も 1 を返す。ログに「テストが実際に走って
# 失敗した」証跡があるときだけ fail に写像し、それ以外は error に倒す。
#
# 判定に使う文字列:
#   'Tests:.*failed'   Jest のサマリ行（例: `Tests: 1 failed, 3 passed, 4 total`）
#   'Test suites?:.*failed'  スイート単位の失敗（テストが 1 件も走らずスイートが落ちた場合も含む）
# のうち前者だけを fail とする。後者だけが出ている場合は、テストファイルの
# import が解決できない・コンテナが起動しないといった「走れなかった」側の可能性が
# 高いため error に残す。
gate_fail_if_matches "$_test_log" 'Tests:.*[0-9]+ failed'
```

`gate_fail_if_matches` は一致すれば exit 1、しなければログ全文を stderr に出して exit 2 で終わる（`_lib.sh`）。`rm -f` に到達しないので `mktemp` のログが `/tmp` に残るが、これは Phase 1 からの既知項目（`/tmp` に溜まる）と同種なのでここでは扱わない。

- [ ] **Step 2: 実行権限を付けて shellcheck を通す**

```bash
chmod +x scripts/gates/l3-test.sh
shellcheck scripts/gates/l3-test.sh
```

期待: 指摘なしで exit 0。

- [ ] **Step 3: クリーンなツリーで pass することを確認する**

```bash
./scripts/gates/l3-test.sh; echo "exit=$?"
```

期待: `exit=0`。

- [ ] **Step 4: テストを壊して fail になることを確認する（赤確認）**

`apps/api/src/discount/discount.ts` の `MEMBER_DISCOUNT_RATE` 適用を一時的に外す。

```bash
./scripts/gates/l3-test.sh; echo "exit=$?"
git checkout apps/api/src/discount/discount.ts
```

期待: `exit=1`。**`exit=2` が返った場合は `gate_fail_if_matches` のパターンが Jest の出力形式と合っていない。** その場合は実際の出力を見てパターンを直す（正解に合わせてパターンを緩めるのではなく、Jest のサマリ行の実物に合わせる）。

- [ ] **Step 5: Docker を落として error になることを確認する（最重要の確認）**

Docker Desktop を止める必要はない。`DOCKER_HOST` を存在しないソケットに向ければ、バイナリは在るまま到達不能を作れる（`gates.test.sh` で Phase 2 が使っている手）。

```bash
DOCKER_HOST=unix:///nonexistent/docker.sock ./scripts/gates/l3-test.sh; echo "exit=$?"
```

期待: `exit=2`、かつ「Docker デーモンが起動していません」のメッセージが出る。**ここが 1 になったら、このゲートは Docker 障害を欠陥検出として記録する。** 先に進まずに直す。

- [ ] **Step 6: `gates.list.sh` に追加する**

```bash
GATE_ORDER=(l2-install l1-typecheck l1-lint l2-semgrep l2-osv l2-gitleaks l3-test)
```

`l3-openapi-drift` は Task 6 で追加する。

- [ ] **Step 7: `gates.test.sh` に L3 固有のテストを足す**

既存の 3 つのループ（クリーンで pass / ツールが無いとき error / `/` から呼んでも pass）は `GATE_ORDER` を回しているので、Step 6 の追加で自動的に `l3-test` を含む。Docker デーモン到達不能のループには明示的に足す。

```bash
# --- Docker ゲートはデーモンに到達できないとき error(2) ---
for gate in l2-semgrep l2-osv l2-gitleaks l3-test; do
```

- [ ] **Step 8: `gates.test.sh` を実行する**

```bash
./scripts/gates/gates.test.sh
```

期待: 全件成功。件数が Phase 2 の 27 件から増えていること（`l3-test` の分）。

- [ ] **Step 9: 既存ケースが退行していないことを確認する**

ハーネスやゲート一覧を変えたら、既に `match` だったケースを再実行する（Phase 1 で実際に退行させた）。

```bash
git add -A && git commit -m "feat: l3-test ゲートを追加"
./verification/run-case.sh L1-05-unchecked-index
```

期待: JSON が返り、`claimVerdict` が `match`。**ここで `l3-test` の期待値が `expect.yml` に無いため `configVerdict` は `mismatch` になるが、それは Task 9 で全ケースの `expect.yml` を更新して解消する。** `claimVerdict` が `match` であることだけを確認する。

- [ ] **Step 10: コミット**

```bash
git add scripts/gates/
git commit -m "feat: l3-test ゲートと exit code 契約テスト"
```

---

## Task 3: `GET /orders/:id` と所有者チェック、FK 違反の処理

**Files:**
- Create: `apps/api/test/orders.e2e-spec.ts`
- Modify: `apps/api/src/orders/orders.controller.ts`
- Modify: `apps/api/src/orders/orders.service.ts`
- Modify: `apps/api/package.json`

**Interfaces:**
- Consumes: Task 1 の `setup-db.ts` と `jest.config.ts` の `e2e` プロジェクト
- Produces: `OrdersService.findOneForUser(userId: string, orderId: string): Promise<OrderResponseDto>`。所有者でなければ `ForbiddenException`、存在しなければ `NotFoundException` を投げる。
- Produces: `OrdersController.findOne(request: AuthenticatedRequest, id: string): Promise<OrderResponseDto>` — `@Get(':id')`
- Produces: `OrdersService.create` は FK 違反（P2003）で `BadRequestException` を投げる。

このタスクは 2 つの申し送りを同時に解消する。

- 設計書 §9 の `L3-03` 申し送り → 403 を返す経路を作る（brainstorming で (a) を選択済み）
- 申し送り #12 → `create` が存在しないユーザー ID で 500 を返す

**両方とも「先に e2e を書いて、現状の壊れ方を実測してから直す」順序で進める。** 500 を実測せずに直すと、「L3 が本当にこれを見ているのか」の証拠が残らない。

- [ ] **Step 1: 依存を追加する**

```bash
pnpm add -D --filter api supertest@7.2.2 @types/supertest@7.2.1
```

- [ ] **Step 2: e2e テストを書く（この時点では落ちる）**

```ts
// apps/api/test/orders.e2e-spec.ts
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';

describe('Orders (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let memberId: string;
  let otherId: string;
  let memberOrderId: string;
  let otherOrderId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    // main.ts の bootstrap と同じ ValidationPipe を張る。ここを揃えないと、
    // e2e は本番と違う入力検証の下で走ることになる。
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(async () => {
    await prisma.order.deleteMany();
    await prisma.user.deleteMany();

    const member = await prisma.user.create({
      data: { email: 'member@example.com', name: '会員', isMember: true },
    });
    const other = await prisma.user.create({
      data: { email: 'other@example.com', name: '他人', isMember: true },
    });
    memberId = member.id;
    otherId = other.id;

    const memberOrder = await prisma.order.create({
      data: { userId: memberId, productName: 'キーボード', unitPrice: 1200, quantity: 1 },
    });
    const otherOrder = await prisma.order.create({
      data: { userId: otherId, productName: 'マウス', unitPrice: 2000, quantity: 1 },
    });
    memberOrderId = memberOrder.id;
    otherOrderId = otherOrder.id;
  });

  it('自分の注文は 200 で取得できる', async () => {
    const response = await request(app.getHttpServer())
      .get(`/orders/${memberOrderId}`)
      .set('x-user-id', memberId);

    expect(response.status).toBe(200);
    expect(response.body.productName).toBe('キーボード');
    expect(response.body.discountedTotal).toBe(1080);
  });

  it('他人の注文は 403 で拒否する', async () => {
    const response = await request(app.getHttpServer())
      .get(`/orders/${otherOrderId}`)
      .set('x-user-id', memberId);

    expect(response.status).toBe(403);
  });

  it('存在しない注文は 404 を返す', async () => {
    const response = await request(app.getHttpServer())
      .get('/orders/00000000-0000-0000-0000-000000000000')
      .set('x-user-id', memberId);

    expect(response.status).toBe(404);
  });

  it('存在しないユーザーの注文作成は 400 を返す', async () => {
    const response = await request(app.getHttpServer())
      .post('/orders')
      .set('x-user-id', '00000000-0000-0000-0000-000000000000')
      .send({ productName: 'ケーブル', unitPrice: 300, quantity: 2 });

    // 申し送り #12: 現状は Prisma の FK 違反（P2003）が未処理で 500 になる。
    expect(response.status).toBe(400);
  });
});
```

- [ ] **Step 3: 実行して落ちることを確認する（現状の壊れ方を実測）**

```bash
pnpm --filter api exec jest --selectProjects e2e
```

期待: 4 件中 3 件が FAIL する。

| テスト | 現状の実測 | 理由 |
|---|---|---|
| 自分の注文は 200 | FAIL（404） | `GET /orders/:id` のルートが無い |
| 他人の注文は 403 | FAIL（404） | 同上 |
| 存在しない注文は 404 | PASS（偶然） | ルートが無いので 404。**実装後も 404 であることを Step 5 で改めて確認する** |
| 不正ユーザーの作成は 400 | FAIL（500） | 申し送り #12 |

**「存在しない注文は 404」が現時点で通ってしまう点に注意する。** ルートが無いことによる 404 と、実装が正しく 404 を返すことは別である。このテストは実装後にはじめて意味を持つ。実測値（特に不正ユーザーの 500）を控えておく。

- [ ] **Step 4: 実装する**

```ts
// apps/api/src/orders/orders.service.ts の変更部分

// 冒頭の import に追加
import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
```

`OrdersService` に追加するメソッド:

```ts
  /**
   * 注文を 1 件取得する。所有者でなければ拒否する。
   *
   * 見つからない場合と他人の注文である場合を区別して返す。実運用では
   * 存在の有無を漏らさないため両方 404 に倒す設計もありうるが、ここでは
   * 検証対象である手順書・設計書の記述（403 を返す経路を作る）に合わせる。
   */
  async findOneForUser(userId: string, orderId: string): Promise<OrderResponseDto> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { user: true },
    });

    if (order === null) {
      throw new NotFoundException('注文が見つかりません');
    }
    if (order.userId !== userId) {
      throw new ForbiddenException('この注文を参照する権限がありません');
    }

    return toOrderResponse(order);
  }
```

`create` の変更:

```ts
  /** 注文を作成し、会員割引を適用した合計付きで返す */
  async create(userId: string, dto: CreateOrderDto): Promise<OrderResponseDto> {
    try {
      const order = await this.prisma.order.create({
        data: {
          userId,
          productName: dto.productName,
          unitPrice: dto.unitPrice,
          quantity: dto.quantity,
        },
        include: { user: true },
      });

      return toOrderResponse(order);
    } catch (error) {
      // P2003 は外部キー制約違反。存在しないユーザー ID を渡された場合に起きる。
      // 未処理のままだと 500 になり、クライアントの誤りがサーバの障害として
      // 記録される（申し送り #12）。
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') {
        throw new BadRequestException('指定されたユーザーが存在しません');
      }
      throw error;
    }
  }
```

コントローラ:

```ts
// apps/api/src/orders/orders.controller.ts
import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
```

```ts
  /** 認証済みユーザー自身の注文を 1 件取得 */
  @Get(':id')
  findOne(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ): Promise<OrderResponseDto> {
    return this.ordersService.findOneForUser(request.userId, id);
  }
```

**`@Get()` より後ろに置くこと。** NestJS はルートを宣言順に照合するので、`@Get(':id')` を先に書くと `GET /orders` 以外のすべてが `:id` に吸われる。

- [ ] **Step 5: 実行して通ることを確認する**

```bash
pnpm --filter api exec jest --selectProjects e2e
```

期待: 4 件とも PASS。

- [ ] **Step 6: 所有者チェックを外して赤くなることを確認する（赤確認）**

`findOneForUser` の `if (order.userId !== userId)` ブロックを一時的にコメントアウトする。

```bash
pnpm --filter api exec jest --selectProjects e2e
```

期待: 「他人の注文は 403 で拒否する」が FAIL（200 が返る）。確認したら戻す。

**この壊し方が `L3-03-authz-bypass` の `case.patch` そのものになる。** ここで得た diff を Task 9 で使うので、`git diff` の出力を控えておく。

- [ ] **Step 7: 単体テストが実 DB 無しで通ることを確認する**

```bash
pnpm --filter api exec jest --selectProjects unit
```

期待: 既存の `orders.service.spec.ts` が引き続き PASS。`create` に try/catch を足したので、モックが投げないパスは変わっていないはず。落ちた場合はモックの都合であり実装の問題ではないので、テスト側を直す。

- [ ] **Step 8: findings に記録する**

`phase0-findings.md` の §1 に追記する。

- 申し送り #12 を解消したこと。**500 を実測してから直した**こと（実測値を引用）
- 手順書 §4 は e2e で NestJS アプリを立てる手順を書いていない。`main.ts` の `bootstrap` にある `ValidationPipe` の設定を `createTestingModule` 側で再現しないと、**e2e が本番と違う入力検証の下で走る**。これは「テストは緑だが本番は守られていない」を作る型なので修正提案候補になる

- [ ] **Step 9: コミット**

```bash
git add apps/api docs/superpowers/phase0-findings.md pnpm-lock.yaml
git commit -m "feat: GET /orders/:id の所有者チェックと FK 違反の 400 写像"
```

---

## Task 4: `AuthGuard` の単体テストと 401 の e2e

**Files:**
- Create: `apps/api/src/auth/auth.guard.spec.ts`
- Modify: `apps/api/test/orders.e2e-spec.ts`

**Interfaces:**
- Consumes: `AuthGuard`（`apps/api/src/auth/auth.guard.ts`、変更しない）
- Produces: なし（テストのみ）

申し送り #9 の解消。`AuthGuard` は認可の入口でありながら、これまで単体テストも e2e も無い状態だった。

- [ ] **Step 1: 単体テストを書く**

```ts
// apps/api/src/auth/auth.guard.spec.ts
import { UnauthorizedException, type ExecutionContext } from '@nestjs/common';
import { AuthGuard, type AuthenticatedRequest } from './auth.guard';

/** switchToHttp().getRequest() が指定のリクエストを返す ExecutionContext を作る */
function contextWith(headers: Record<string, string | string[] | undefined>): ExecutionContext {
  const request = { headers } as unknown as AuthenticatedRequest;
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
}

describe('AuthGuard', () => {
  const guard = new AuthGuard();

  it('x-user-id があれば通し、request に userId を載せる', () => {
    const context = contextWith({ 'x-user-id': 'user-1' });

    expect(guard.canActivate(context)).toBe(true);
    expect(context.switchToHttp().getRequest<AuthenticatedRequest>().userId).toBe('user-1');
  });

  it('x-user-id が無ければ UnauthorizedException を投げる', () => {
    expect(() => guard.canActivate(contextWith({}))).toThrow(UnauthorizedException);
  });

  it('x-user-id が空文字なら UnauthorizedException を投げる', () => {
    expect(() => guard.canActivate(contextWith({ 'x-user-id': '' }))).toThrow(UnauthorizedException);
  });

  it('x-user-id が配列（ヘッダ重複）なら UnauthorizedException を投げる', () => {
    // express はヘッダが重複すると配列を返す。typeof !== 'string' の分岐を通る。
    expect(() => guard.canActivate(contextWith({ 'x-user-id': ['a', 'b'] }))).toThrow(
      UnauthorizedException,
    );
  });
});
```

- [ ] **Step 2: 実行して通ることを確認する**

```bash
pnpm --filter api exec jest --selectProjects unit
```

期待: 4 件とも PASS。

- [ ] **Step 3: ガードを壊して赤くなることを確認する（赤確認）**

`auth.guard.ts` の `if (typeof userId !== 'string' || userId.length === 0)` を `if (false)` に一時的に置き換える。

```bash
pnpm --filter api exec jest --selectProjects unit
```

期待: 3 件が FAIL（例外を期待して投げられない）。確認したら戻す。

- [ ] **Step 4: e2e に 401 を足す**

`apps/api/test/orders.e2e-spec.ts` に追加する。

```ts
  it('x-user-id が無ければ 401 を返す', async () => {
    const response = await request(app.getHttpServer()).get('/orders');

    expect(response.status).toBe(401);
  });

  it('x-user-id が無ければ個別取得も 401 を返す', async () => {
    const response = await request(app.getHttpServer()).get(`/orders/${memberOrderId}`);

    expect(response.status).toBe(401);
  });
```

- [ ] **Step 5: 実行して通ることを確認する**

```bash
pnpm --filter api exec jest --selectProjects e2e
```

期待: 6 件とも PASS。

- [ ] **Step 6: コミット**

```bash
git add apps/api
git commit -m "test: AuthGuard の単体テストと 401 の e2e（申し送り #9）"
```

---

## Task 5: fast-check によるプロパティベーステスト

**Files:**
- Modify: `apps/api/src/discount/discount.spec.ts`
- Modify: `package.json`（ルート）

**Interfaces:**
- Consumes: `applyDiscount(price: number, isMember: boolean): number`（`apps/api/src/discount/discount.ts`、変更しない）
- Produces: なし（テストのみ）

手順書 §4.5 の検証。`FC_NUM_RUNS` を環境変数化して「毎 PR は 100、nightly は 10000」という探索と回帰の分離が実際に機能するかを見る。

- [ ] **Step 1: 依存を追加する**

手順書 §4.5 は `pnpm add -Dw fast-check` と書く。`-w` はルートのワークスペースに入れる指定である。

```bash
pnpm add -Dw fast-check@4.9.0
```

`-w` が pnpm 11 で受け付けられない場合は `pnpm add -D fast-check@4.9.0` をリポジトリルートで実行する。**受け付けられなかった場合はその事実を findings に記録する**（手順書のコマンドがそのまま動かないことになる）。

- [ ] **Step 2: プロパティを書く**

既存の `apps/api/src/discount/discount.spec.ts` の末尾に追加する（既存のテストは消さない）。

```ts
import fc from 'fast-check';

// 手順書 §4.5 の指定どおり環境変数で回数を切り替える。
// 毎 PR は 100（数秒）、nightly は FC_NUM_RUNS=10000 で深く探索する。
const NUM_RUNS = Number(process.env.FC_NUM_RUNS ?? 100);

describe('applyDiscount のプロパティ', () => {
  it('割引後の価格は元の価格を超えない', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 1_000_000 }),
        fc.boolean(),
        (price, isMember) => applyDiscount(price, isMember) <= price,
      ),
      { numRuns: NUM_RUNS },
    );
  });

  it('非会員の価格は常に元のまま', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 1_000_000 }),
        (price) => applyDiscount(price, false) === price,
      ),
      { numRuns: NUM_RUNS },
    );
  });

  it('割引後の価格は非負の整数', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 1_000_000 }),
        fc.boolean(),
        (price, isMember) => {
          const result = applyDiscount(price, isMember);
          return Number.isInteger(result) && result >= 0;
        },
      ),
      { numRuns: NUM_RUNS },
    );
  });
});
```

- [ ] **Step 3: 実行して通ることを確認する**

```bash
pnpm --filter api exec jest --selectProjects unit
```

期待: PASS。

- [ ] **Step 4: 実装を壊してプロパティが反例を見つけることを確認する（赤確認）**

`discount.ts` の `Math.floor` を `Math.ceil` に、かつ割引率を `1 + MEMBER_DISCOUNT_RATE` に一時的に変える（割引後が元より高くなる）。

```bash
pnpm --filter api exec jest --selectProjects unit
```

期待: 「割引後の価格は元の価格を超えない」が FAIL し、fast-check が縮小した反例（`Counterexample: [1000,true]` の形）を出す。確認したら戻す。

**反例が出ずに通ってしまった場合は、生成範囲がプロパティを刺していない。** その場合は `min` / `max` を見直す（`MEMBER_DISCOUNT_MIN_PRICE` は 1000 なので、生成範囲がそれを跨いでいる必要がある）。

- [ ] **Step 5: `FC_NUM_RUNS` が効くことを確認する**

```bash
FC_NUM_RUNS=10000 pnpm --filter api exec jest --selectProjects unit
```

期待: PASS。100 のときより明らかに時間がかかる（実行時間を控えて findings に書く）。

**時間が変わらない場合は環境変数が読まれていない。** ts-jest 経由でも `process.env` は素通しなので、読まれていないなら綴りかスコープの問題である。

- [ ] **Step 6: findings に記録する**

- `pnpm add -Dw` が pnpm 11 で通ったか
- `FC_NUM_RUNS` 100 と 10000 の実行時間の差（手順書 §4.5 の「毎 PR は数秒」という主張の実測値）
- 反例が出たときの出力形式（手順書は「失敗した反例は必ずテストコードに固定化してください」と書くので、その固定化が現実的かどうか）

- [ ] **Step 7: コミット**

```bash
git add apps/api package.json pnpm-lock.yaml docs/superpowers/phase0-findings.md pnpm-workspace.yaml
git commit -m "test: fast-check によるプロパティベーステスト（手順書 §4.5）"
```

---

## Task 6: OpenAPI 型生成と `l3-openapi-drift.sh`

**Files:**
- Create: `apps/api/src/openapi.ts`
- Create: `apps/web/src/api/schema.d.ts`（生成物）
- Create: `scripts/gates/l3-openapi-drift.sh`
- Modify: `apps/api/src/orders/dto/order-response.dto.ts`
- Modify: `apps/api/src/orders/dto/create-order.dto.ts`
- Modify: `apps/api/src/orders/orders.controller.ts`
- Modify: `apps/web/src/api/client.ts`
- Modify: `apps/api/package.json` / `apps/web/package.json`
- Modify: `scripts/gates/gates.list.sh` / `scripts/gates/gates.test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `pnpm --filter api run generate:openapi` がリポジトリルートに `openapi.json` を出力する
- Produces: `apps/web/src/api/schema.d.ts` は `openapi-typescript` の生成物。`paths` 型をエクスポートする
- Produces: `apps/web/src/api/client.ts` の `OrderView` は `schema.d.ts` から導出した型のエイリアスになる（申し送り #10 の解消）
- Produces: `scripts/gates/l3-openapi-drift.sh`。`GATE_ORDER` の 8 番目に入る

**手順書 §4.4 が書いていない前提が 2 つある。**

1. `@nestjs/swagger` は実行時のデコレータメタデータでスキーマを組み立てるので、**`interface` の DTO は OpenAPI に出ない。** 現在の `OrderResponseDto` は `interface` なので `class` へ変え、`@ApiProperty` を付ける必要がある。
2. **ゲートが生成物を書き換えるため、作業ツリーが汚れる。** 検証ハーネスは検証ブランチから元ブランチへ `git checkout` で戻るので、追跡ファイルが汚れたままだと cleanup が失敗し、ケースが exit 2 になる。ゲート側で必ず復元する。

- [ ] **Step 1: 依存を追加する**

```bash
pnpm add -D --filter api @nestjs/swagger@11.4.6
pnpm add -D --filter web openapi-typescript@7.13.0
```

- [ ] **Step 2: DTO を OpenAPI に出せる形にする**

```ts
// apps/api/src/orders/dto/order-response.dto.ts
import { ApiProperty } from '@nestjs/swagger';
import type { OrderStatus } from '@repo/shared';

/**
 * 注文一覧・注文作成のレスポンス
 *
 * class にしているのは @nestjs/swagger が実行時のデコレータメタデータから
 * スキーマを組み立てるためである。interface は型消去で実行時に残らないので
 * OpenAPI に 1 つも項目が出ない。手順書 §4.4 はこの前提に触れていない。
 */
export class OrderResponseDto {
  @ApiProperty()
  id!: string;

  @ApiProperty()
  productName!: string;

  @ApiProperty()
  unitPrice!: number;

  @ApiProperty()
  quantity!: number;

  @ApiProperty({ enum: ['PENDING', 'PAID', 'CANCELLED'] })
  status!: OrderStatus;

  /** 会員割引を適用した合計金額 */
  @ApiProperty()
  discountedTotal!: number;
}
```

`CreateOrderDto` にも `@ApiProperty` を足す（class-validator のデコレータは OpenAPI のスキーマにはならない）。

```ts
// apps/api/src/orders/dto/create-order.dto.ts
import { ApiProperty } from '@nestjs/swagger';
import { IsInt, IsString, MaxLength, Min, MinLength } from 'class-validator';

/** 注文作成の入力 */
export class CreateOrderDto {
  @ApiProperty({ minLength: 1, maxLength: 100 })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  productName!: string;

  @ApiProperty({ minimum: 0 })
  @IsInt()
  @Min(0)
  unitPrice!: number;

  @ApiProperty({ minimum: 1 })
  @IsInt()
  @Min(1)
  quantity!: number;
}
```

`OrderResponseDto` を `import type` していた箇所（`orders.controller.ts` / `orders.service.ts`）は、class になったので値としての import に変える必要はない（型としてしか使っていない）。ただしコントローラでは戻り値型を Swagger に伝えるため値として使う。

```ts
// apps/api/src/orders/orders.controller.ts
import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiOkResponse } from '@nestjs/swagger';
import { AuthGuard, type AuthenticatedRequest } from '../auth/auth.guard';
import { CreateOrderDto } from './dto/create-order.dto';
import { OrderResponseDto } from './dto/order-response.dto';
import { OrdersService } from './orders.service';
```

各ハンドラに戻り値のスキーマを明示する。**これが無いと OpenAPI のレスポンスが空になり、`schema.d.ts` に型が出ないまま drift ゲートが「差分なし」で緑になる。** 緑と守っているは別物の典型なので Step 6 の赤確認で必ず確かめる。

```ts
  @Get()
  @ApiOkResponse({ type: [OrderResponseDto] })
  findAll(@Req() request: AuthenticatedRequest): Promise<OrderResponseDto[]> { /* 既存のまま */ }

  @Get(':id')
  @ApiOkResponse({ type: OrderResponseDto })
  findOne(/* 既存のまま */) { /* 既存のまま */ }

  @Post()
  @ApiOkResponse({ type: OrderResponseDto })
  create(/* 既存のまま */) { /* 既存のまま */ }
```

- [ ] **Step 3: OpenAPI 出力の CLI を書く**

```ts
// apps/api/src/openapi.ts
import 'reflect-metadata';
import { writeFileSync } from 'node:fs';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';

const OUTPUT = `${__dirname}/../../../openapi.json`;

async function main(): Promise<void> {
  // listen しない。スキーマを組み立てるだけなので DB 接続も不要である。
  const app = await NestFactory.create(AppModule, { logger: false });
  const config = new DocumentBuilder().setTitle('Orders API').setVersion('1.0').build();
  const document = SwaggerModule.createDocument(app, config);

  // 生成物の差分で drift を検出するので、キーの順序が実行ごとに揺れてはいけない。
  // JSON.stringify は挿入順を保つため、NestJS が同じ順序でメタデータを集める限り安定する。
  writeFileSync(OUTPUT, `${JSON.stringify(document, null, 2)}\n`);
  await app.close();
}

main().catch((cause: unknown) => {
  // eslint-disable-next-line no-console -- CLI なのでログ以外に伝える手段が無い
  console.error('OpenAPI の生成に失敗しました', cause);
  process.exit(1);
});
```

`apps/api/package.json` の `scripts` に追加する。

```json
    "generate:openapi": "ts-node -P tsconfig.build.json src/openapi.ts"
```

- [ ] **Step 4: 手順書 §4.4 の手順を手で流して生成物を作る**

```bash
pnpm --filter api run generate:openapi
pnpm --filter web exec openapi-typescript ../../openapi.json -o src/api/schema.d.ts
```

期待: `openapi.json` と `apps/web/src/api/schema.d.ts` ができる。`schema.d.ts` を開いて **`/orders` と `/orders/{id}` の両方**があり、レスポンスに `discountedTotal` などの項目が並んでいることを目視する。**項目が空だったら Step 2 の `@ApiProperty` か `@ApiOkResponse` が効いていない。**

`openapi.json` は生成物なので `.gitignore` に足す。`schema.d.ts` は追跡する（差分を見る対象なので）。

```
# .gitignore に追加
openapi.json
```

- [ ] **Step 5: `client.ts` を生成型に差し替える（申し送り #10）**

```ts
// apps/web/src/api/client.ts
import type { paths } from './schema';

/**
 * 注文一覧の表示に使う 1 件分のデータ
 *
 * 生成された OpenAPI の型から導出する。手で書いた interface に戻すと、
 * API 側の DTO が変わっても Web 側が気づかない状態に戻る（申し送り #10）。
 */
export type OrderView =
  paths['/orders']['get']['responses'][200]['content']['application/json'][number];

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

/** 指定ユーザーの注文一覧を取得する */
export async function fetchOrders(userId: string): Promise<OrderView[]> {
  const response = await fetch(`${API_BASE_URL}/orders`, {
    headers: { 'x-user-id': userId },
  });

  if (!response.ok) {
    throw new Error(`注文の取得に失敗しました（HTTP ${response.status}）`);
  }

  return (await response.json()) as OrderView[];
}
```

生成された `schema.d.ts` の実際のキー名（`responses` の書き方は `openapi-typescript` の版で異なる）に合わせて型のパスを調整する。**`pnpm turbo typecheck` が通ることで正しさを確認する。**

`as OrderView[]` のキャスト自体は残る（`fetch` の戻りは `unknown` 相当なので実行時検証を入れない限り消せない）。**申し送り #10 が問題にしていたのは「手書きの型と API の DTO がずれても誰も気づかない」ことなので、型の出所が生成物になった時点で解消している。** 実行時検証（zod 等）は手順書の範囲外なので入れない。

- [ ] **Step 6: ゲートを書く**

```bash
#!/usr/bin/env bash
# L3: OpenAPI 生成物の drift 検出（手順書 §4.4 ③）
#
# API 側の DTO を変えたのに Web 側の生成型を更新していない状態を検出する。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm

SCHEMA=apps/web/src/api/schema.d.ts

# このゲートは追跡ファイル（schema.d.ts）を書き換える。検証ハーネスは検証ブランチから
# 元ブランチへ git checkout で戻るので、汚れたまま終わるとその checkout が失敗し、
# ケース全体が exit 2 になる（run-case.sh の復帰ガード）。どの経路で終わっても
# 必ず戻す。手順書 §4.4 はゲートが作業ツリーを汚す点に触れていない。
restore_schema() {
  git checkout --quiet -- "$SCHEMA" 2>/dev/null || true
}
trap restore_schema EXIT

_log=$(mktemp)
if ! pnpm --filter api run generate:openapi >"$_log" 2>&1; then
  printf 'gate error: OpenAPI の生成に失敗しました\n' >&2
  cat "$_log" >&2
  rm -f "$_log"
  exit "$GATE_ERROR"
fi

if ! pnpm --filter web exec openapi-typescript ../../openapi.json -o src/api/schema.d.ts >>"$_log" 2>&1; then
  printf 'gate error: 型の生成に失敗しました\n' >&2
  cat "$_log" >&2
  rm -f "$_log"
  exit "$GATE_ERROR"
fi
rm -f "$_log"

# 手順書 §4.4 ③ のコマンド。差分があれば 1、無ければ 0。
# git diff の非ゼロは 1 だけを fail とし、他（128 = リポジトリ外など）は error に倒す。
git diff --exit-code "$SCHEMA"
gate_finish "$?" 1
```

- [ ] **Step 7: 実行権限と shellcheck**

```bash
chmod +x scripts/gates/l3-openapi-drift.sh
shellcheck scripts/gates/l3-openapi-drift.sh
```

- [ ] **Step 8: クリーンなツリーで pass することを確認する**

```bash
git add -A && git commit -m "feat: OpenAPI 型生成（手順書 §4.4）"
./scripts/gates/l3-openapi-drift.sh; echo "exit=$?"
git status --porcelain
```

期待: `exit=0`、かつ `git status --porcelain` が**空**（ゲートが作業ツリーを汚していない）。汚れが残っていたら trap が効いていない。

- [ ] **Step 9: DTO を変えて赤くなることを確認する（赤確認）**

`OrderResponseDto` に項目を 1 つ足す（`@ApiProperty() note!: string;`）。生成物は更新しない。

```bash
./scripts/gates/l3-openapi-drift.sh; echo "exit=$?"
git status --porcelain
```

期待: `exit=1`、かつ `git status --porcelain` に `schema.d.ts` が**出ない**（trap が復元している。`order-response.dto.ts` の変更は残る）。確認したら DTO の変更を戻す。

**この赤確認は Task 9 の `L3-02-openapi-drift` の `case.patch` の元になる。** diff を控えておく。

- [ ] **Step 10: `gates.list.sh` と `gates.test.sh` を更新する**

```bash
GATE_ORDER=(l2-install l1-typecheck l1-lint l2-semgrep l2-osv l2-gitleaks l3-test l3-openapi-drift)
```

`gates.test.sh` の Docker デーモンのループには `l3-openapi-drift` を**足さない**（Docker を使わないゲートなので、`DOCKER_HOST` を壊しても pass する）。

```bash
./scripts/gates/gates.test.sh
```

期待: 全件成功。

- [ ] **Step 11: 型チェックと lint が通ることを確認する**

```bash
pnpm turbo typecheck
pnpm lint
```

期待: 両方 exit 0。`schema.d.ts` は生成物だが `apps/web` の tsconfig の `include` に入るので型チェックの対象になる。lint で生成物が引っかかる場合は `apps/web/eslint.config.mjs` の `ignores` に `src/api/schema.d.ts` を足す（**ルートの `eslint.config.mjs` には足さない**。Global Constraints）。

- [ ] **Step 12: 申し送り #24 の確認（tsconfig / jest 設定に触れたため）**

```bash
git add -A && git commit -m "feat: l3-openapi-drift ゲート"
./verification/run-case.sh L1-05-unchecked-index
```

期待: JSON の `blockedBy` に `l1-typecheck` が入る（`l1-typecheck` が fail を返している）。

- [ ] **Step 13: findings に記録する**

- 手順書 §4.4 は DTO が `class` である必要（`@ApiProperty` / `@ApiOkResponse`）に触れていない。`interface` のままだと OpenAPI に項目が 1 つも出ず、**drift ゲートは差分ゼロで緑になる**
- 手順書 §4.4 ③ のコマンドは生成物を書き換えるので、ゲートとして使うと作業ツリーが汚れる。ハーネス側の復帰処理と衝突する
- `openapi.json` の出力先（手順書はリポジトリルート）を追跡するかどうかに触れていない

- [ ] **Step 14: コミット**

```bash
git add -A
git commit -m "docs: OpenAPI 型生成で判明した手順書の記述漏れを記録"
```

---

## Task 7: Playwright（`GATE_ORDER` 外）

**Files:**
- Create: `apps/web/playwright.config.ts`
- Create: `apps/web/e2e/orders.spec.ts`
- Create: `scripts/gates/l3-e2e-web.sh`
- Modify: `apps/api/prisma/seed.ts`（ユーザー ID の固定）
- Modify: `apps/web/package.json`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `scripts/gates/l3-e2e-web.sh`。**`GATE_ORDER` にも `GATE_DETECTION` にも入れない。** Phase 5（nightly 相当）で実行する。

手順書 §4.1 は Playwright を「△ 主要導線のみ」、付録 L3 は「主要導線のみ PR、フルは nightly」とする。全ケースで Postgres + API + Vite + ブラウザを起こすと `run-all.sh` の所要時間が跳ね、error(2) の発生源も増えるため、Phase 3 では**スクリプトと導線 1 本を用意するに留める**。

- [ ] **Step 1: 依存とブラウザを入れる**

```bash
pnpm add -D --filter web @playwright/test@1.62.0
pnpm --filter web exec playwright install chromium
```

`playwright install` はブラウザバイナリをユーザーのキャッシュ（`~/Library/Caches/ms-playwright`）に置く。リポジトリには入らない。

- [ ] **Step 2: 設定を書く**

```ts
// apps/web/playwright.config.ts
import { defineConfig } from '@playwright/test';

// 手順書 §4.1 は「主要導線のみ」とだけ書き、E2E がアプリと DB をどう起こすかに
// 触れていない。ここでは webServer で API と Vite を起こし、DB は
// docker compose（pnpm db:up）で先に立っている前提にする。
export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  use: { baseURL: 'http://localhost:5173' },
  webServer: [
    {
      command: 'pnpm --filter api run start:dev',
      url: 'http://localhost:3000/orders',
      // AuthGuard が x-user-id を要求するので 401 が返る。到達確認としては
      // これで十分なので、2xx 以外も「起動した」とみなす。
      ignoreHTTPSErrors: true,
      reuseExistingServer: true,
      timeout: 60_000,
    },
    {
      command: 'pnpm --filter web run dev',
      url: 'http://localhost:5173',
      reuseExistingServer: true,
      timeout: 60_000,
    },
  ],
});
```

`url` に対する到達判定が 401 を受け付けない場合は `command` のみを指定して `port` で待つ形に変える。**変更した場合は理由をコメントに残す。**

- [ ] **Step 3: seed のユーザー ID を固定する**

`apps/web/src/App.tsx` は**ユーザー ID を画面から手入力する**作りで、固定 ID を持たない（事前確認 I）。一方 `apps/api/prisma/seed.ts` は `@default(uuid())` に任せているので、投入されるたびに ID が変わる。このままだと Playwright 側が入力すべき ID を知る手段が無い。

seed 側の ID を固定する。冪等性（`deleteMany` してから投入）は変わらない。

```ts
// apps/api/prisma/seed.ts
// e2e から参照できるよう ID を固定する。画面はユーザー ID の手入力を求める作りなので、
// 自動採番の uuid だと Playwright 側が入力すべき値を知る手段が無い。
const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const GUEST_ID = '22222222-2222-4222-8222-222222222222';
```

`prisma.user.create` の `data` にそれぞれ `id: MEMBER_ID` / `id: GUEST_ID` を足す。

- [ ] **Step 4: 主要導線を 1 本書く**

```ts
// apps/web/e2e/orders.spec.ts
import { expect, test } from '@playwright/test';

// seed.ts で固定した会員ユーザーの ID。
const MEMBER_ID = '11111111-1111-4111-8111-111111111111';

// 主要導線: ユーザー ID を入力すると、そのユーザーの注文一覧が
// 割引適用後の合計付きで表示される。
// 前提: pnpm db:up → db:migrate → db:seed が済んでいること。
test('注文一覧に割引適用後の合計が表示される', async ({ page }) => {
  await page.goto('/');

  await page.getByLabel('ユーザー ID').fill(MEMBER_ID);

  await expect(page.getByText('キーボード')).toBeVisible();
  // 1200 * 1 = 1200 は閾値以上なので 10% 引きで 1080
  await expect(page.getByText('1080 円')).toBeVisible();
});
```

`getByLabel` が効くのは `App.tsx` が `<label>ユーザー ID <input /></label>` の形で input を包んでいるため。ラベルの関連付けが取れない場合は `getByRole('textbox')` に変える。

- [ ] **Step 5: ローカルで通ることを確認する**

```bash
pnpm db:up
pnpm --filter api run db:migrate
pnpm --filter api run db:seed
pnpm --filter web exec playwright test
```

期待: 1 件 PASS。

- [ ] **Step 6: 表示を壊して赤くなることを確認する（赤確認）**

`OrderList.tsx` の `{order.discountedTotal} 円` を `{order.unitPrice} 円` に一時的に変える。

```bash
pnpm --filter web exec playwright test
```

期待: FAIL（`1080 円` が見つからない）。確認したら戻す。

- [ ] **Step 7: ゲートスクリプトを書く**

```bash
#!/usr/bin/env bash
# L3: Web の E2E（手順書 §4.1「△ 主要導線のみ」）
#
# GATE_ORDER には入れない。手順書 §4.1 と付録は Playwright を「主要導線のみ PR、
# フルは nightly」と位置づけており、全検証ケースで Postgres + API + Vite +
# ブラウザを起こすと run-all.sh の所要時間が跳ねるため、Phase 5 の nightly 検証で
# 実行する。実行手段だけをここに用意しておく。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm
gate_require_docker
gate_require_runnable playwright pnpm --filter web exec playwright --version

_log=$(mktemp)
pnpm --filter web exec playwright test 2>&1 | tee "$_log"
raw="${PIPESTATUS[0]}"

if [ "$raw" -eq 0 ]; then
  rm -f "$_log"
  exit "$GATE_PASS"
fi

# playwright はテスト失敗もサーバ起動失敗も 1 を返す。l3-test と同じ理由で
# ログの証跡を見る。'N failed' はテストが実際に走って落ちたときだけ出る。
gate_fail_if_matches "$_log" '[0-9]+ failed'
```

```bash
chmod +x scripts/gates/l3-e2e-web.sh
shellcheck scripts/gates/l3-e2e-web.sh
```

- [ ] **Step 8: `.gitignore` に Playwright の生成物を足す**

```
apps/web/test-results/
apps/web/playwright-report/
```

- [ ] **Step 9: `gates.list.sh` を変更していないことを確認する**

```bash
grep -n 'l3-e2e-web' scripts/gates/gates.list.sh; echo "grep exit=$?"
```

期待: `grep exit=1`（1 件も無い）。**入れてしまうと全 14 ケースで Playwright が走る。**

- [ ] **Step 10: findings に記録して コミット**

- Playwright を PR ゲートに入れなかった判断と理由（所要時間、error(2) の発生源）
- 手順書 §4.1 は E2E がアプリと DB をどう起こすかに触れていない

```bash
git add -A
git commit -m "feat: Playwright の主要導線 1 本と l3-e2e-web（GATE_ORDER 外）"
```

---

## Task 8: ハーネスの改善（申し送り #26 と #25）

**Files:**
- Modify: `verification/run-case.sh`
- Modify: `verification/run-all.sh`
- Modify: `verification/lib/judge.mjs`
- Modify: `verification/lib/judge.test.mjs`

**Interfaces:**
- Produces: `judge()` の戻りに `detectedBy: string[]`（非ブロックゲートで検出されたゲート名）が加わる
- Produces: `claimVerdict` は、`claimed_gate` が非ブロックゲートを指す場合に `detectedBy` を見る

### 8-1. 経過時間の計測（申し送り #26）

現在の「約 40 分」はログの mtime からの推定でしかない。Phase 3 で Testcontainers が入ると時間が跳ねるので、どこが遅いのかを語れる状態にする。

- [ ] **Step 1: `run-case.sh` にゲート別の経過秒数を出す**

`run_gate` と `run_detection_gate` の両方を変更する。**TSV に列を足さないこと。** `judge.mjs` の `parseActual` は 4 列目以降を `summary` として結合するので、列を挿入すると判定が壊れる。stderr に出す。

```bash
run_gate() {
  local gate="$1"
  local log="$LOGS/$gate.log"
  local started
  started=$SECONDS
  "./scripts/gates/$gate.sh" >"$log" 2>&1
  local code=$?
  printf '  %-20s exit=%s %ss\n' "$gate" "$code" "$((SECONDS - started))" >&2
  local summary
  summary=$(tail -n 1 "$log" | tr -d '\t' | cut -c1-120)
  printf '%s\t%s\t-\t%s\n' "$gate" "$code" "$summary" >>"$ACTUAL"
  return "$code"
}
```

`run_detection_gate` にも同じ計測を入れる（`local detected=false` の前に `started=$SECONDS`、TSV 出力の前に printf）。

`SECONDS` は bash の組み込みでシェル起動からの秒数を返す。外部コマンドを呼ばずに測れる。

- [ ] **Step 2: `run-all.sh` にケース別と全体の経過時間を出す**

ケースのループの中と最後に足す。

```bash
# ループの直前
ALL_STARTED=$SECONDS

# ループ内、run-case.sh の呼び出しを挟む形で
  case_started=$SECONDS
  ./verification/run-case.sh "$case_id" >"$WORK/$case_id.json" 2>"$stderr_log"
  case_status=$?
  cat "$stderr_log" >&2
  printf '--- %s: %s 秒 ---\n' "$case_id" "$((SECONDS - case_started))" >&2

# 最後、cat "$RESULTS" の前
printf '\n全体の所要時間: %s 分 %s 秒\n' "$(((SECONDS - ALL_STARTED) / 60))" "$(((SECONDS - ALL_STARTED) % 60))" >&2
```

- [ ] **Step 3: shellcheck を通して 1 ケースで確認する**

```bash
shellcheck verification/run-case.sh verification/run-all.sh
git add -A && git commit -m "feat: 検証ハーネスに経過時間の計測を追加（申し送り #26）"
./verification/run-case.sh L1-02-explicit-any
```

期待: stderr にゲートごとの `exit=N Ms` が並び、JSON が返る。`claimVerdict` が `match`。

### 8-2. 非ブロックゲートの照合規約（申し送り #25）

`L2-04-new-dependency` は、手順書 §3.3 の設計どおり動いている（`l2-new-deps` が検出している）のに `RESULTS.md` では ❌ になる。`blockedBy` は fail したゲートの集合なので、exit code が常に 0 の非ブロックゲートは構造上そこに入らないためである（§1.26）。

**規約: `claimed_gate` が非ブロックゲートを指す場合、`claimVerdict` / `claimGateVerdict` は「止めたか」ではなく「検出したか」で判定する。** ブロックと検出は別の概念なので `blockedBy` には混ぜず、`detectedBy` を別に持つ。表示でも区別する。

- [ ] **Step 4: `judge.test.mjs` に失敗するテストを書く**

既存のテストの形式に合わせて追加する（`node --test` で走る）。

```js
test('claimed_gate が非ブロックゲートのとき、検出していれば match になる', () => {
  const expected = {
    id: 'L2-04-new-dependency',
    pitfall: '実在する新規依存を追加する',
    claimedLayer: 'L2',
    claimedGate: 'l2-new-deps',
    expect: { 'l2-install': 'pass' },
    expectDetection: { 'l2-new-deps': true },
  };
  const actual = {
    'l2-install': { code: 0, detected: '-', summary: '' },
    'l2-new-deps': { code: 0, detected: 'true', summary: '' },
  };

  const result = judge(expected, actual);

  assert.equal(result.claimGateVerdict, 'match');
  assert.equal(result.claimVerdict, 'match');
  assert.deepEqual(result.detectedBy, ['l2-new-deps']);
  // 「止めた」わけではないので blockedBy には入らない
  assert.deepEqual(result.blockedBy, []);
});

test('claimed_gate が非ブロックゲートで、検出しなければ mismatch になる', () => {
  const expected = {
    id: 'L2-04-new-dependency',
    pitfall: '実在する新規依存を追加する',
    claimedLayer: 'L2',
    claimedGate: 'l2-new-deps',
    expect: { 'l2-install': 'pass' },
    expectDetection: { 'l2-new-deps': false },
  };
  const actual = {
    'l2-install': { code: 0, detected: '-', summary: '' },
    'l2-new-deps': { code: 0, detected: 'false', summary: '' },
  };

  const result = judge(expected, actual);

  assert.equal(result.claimGateVerdict, 'mismatch');
  assert.equal(result.claimVerdict, 'not-caught');
});
```

- [ ] **Step 5: 実行して落ちることを確認する**

```bash
node --test verification/lib/judge.test.mjs
```

期待: 追加した 2 件が FAIL（`detectedBy` が undefined、`claimGateVerdict` が `mismatch`）。

- [ ] **Step 6: `judge.mjs` を変更する**

`judge()` の中、`blockedBy` の算出の後に追加する。

```js
  // 非ブロックゲートで「検出した」ものを別に集める。ブロックと検出は別の概念なので
  // blockedBy には混ぜない。手順書 §3.3 の新規依存検出はブロックを意図しておらず、
  // exit code は常に 0 である。これを blockedBy で測ろうとすると、設計どおり動いて
  // いるケースが原理的に match になりえない（§1.26 / 申し送り #25）。
  const detectedBy = entries
    .filter(isDetectionGate)
    .filter(([, r]) => r.detected === 'true')
    .map(([gate]) => gate);

  const detectingLayers = [...new Set(detectedBy.map(layerOfGate))];
```

`errored` の早期 return にも `detectedBy: []` と `detectingLayers: []` を足す。

`claimVerdict` の算出を変える。

```js
  // 手順書が非ブロックゲートを名指ししているケースは「検出したか」で判定する。
  // それ以外は従来どおり「止めたか」で判定する。
  const claimIsDetection =
    expected.claimedGate !== '' && isDetectionGate([expected.claimedGate, actual[expected.claimedGate] ?? {}]);
  const caughtBy = claimIsDetection ? detectedBy : blockedBy;
  const caughtLayers = claimIsDetection ? detectingLayers : blockingLayers;

  let claimVerdict;
  if (caughtBy.length === 0) {
    claimVerdict = 'not-caught';
  } else if (caughtLayers.includes(expected.claimedLayer)) {
    claimVerdict = 'match';
  } else {
    claimVerdict = 'mismatch';
  }

  let claimGateVerdict;
  if (expected.claimedGate === '') {
    claimGateVerdict = 'n/a';
  } else if (caughtBy.includes(expected.claimedGate)) {
    claimGateVerdict = 'match';
  } else {
    claimGateVerdict = 'mismatch';
  }
```

`isDetectionGate` は `([, r]) => r.detected === 'true' || r.detected === 'false'` なので、`actual` に該当ゲートが無い場合は `{}` を渡して `false` になる（従来の経路に落ちる）。

戻り値に `detectedBy` と `detectingLayers` を足す。

- [ ] **Step 7: テストが通ることを確認する**

```bash
node --test verification/lib/judge.test.mjs
```

期待: 追加分を含めて全件 PASS。**既存のテストが 1 件も落ちていないこと**を確認する（`claimVerdict` の分岐を変えたので、ブロックゲートのケースが巻き添えになっていないか）。

- [ ] **Step 8: `run-all.sh` の表示を変える**

「実際に止めた層」の列に検出のみのゲートが混ざると誤読を招くので、注記を付ける。

```js
    const blocked = r.blockedBy.length > 0 ? r.blockedBy.join(", ") : "（なし）";
    const detected = r.detectedBy.length > 0 ? r.detectedBy.map(g => g + "（検出のみ）").join(", ") : "";
    const caught = [blocked === "（なし）" && detected ? "" : blocked, detected].filter(Boolean).join(", ") || "（なし）";
```

`caught` を表の 4 列目に使う。あわせて `RESULTS.md` のヘッダの「この表が保証していること・していないこと」に 1 項目足す。

```bash
  printf -- '- **「止めた」と「検出した」を区別している。** 非ブロックゲート（`l2-new-deps`）は\n'
  printf '  exit code で欠陥を主張しないので、検出した場合は「（検出のみ）」と注記する。\n'
```

- [ ] **Step 9: `L2-04` で確認する**

```bash
git add -A && git commit -m "feat: 非ブロックゲートを検出で照合する（申し送り #25）"
./verification/run-case.sh L2-04-new-dependency
```

期待: `claimVerdict` と `claimGateVerdict` がどちらも `match`、`detectedBy` が `["l2-new-deps"]`、`blockedBy` が `[]`。

**この変更は `claimed_layer` を書き換えていない。** 手順書の主張（L2 が新規依存を検出する）はそのままで、ハーネス側が「検出」を測れるようになっただけである。

- [ ] **Step 10: findings の §1.26 と申し送り #25 を更新する**

- §1.26 に「Phase 3 で (a) を選択し解消した」旨を追記する（原文は記録として残す）
- CLAUDE.md の「現在地」にある「`L2-04` の ❌ はハーネスの限界」という注記は Task 10 で結果を見てから直す

- [ ] **Step 11: コミット**

```bash
git add -A
git commit -m "docs: 申し送り #25 の結論を記録"
```

---

## Task 9: 検証ケース 3 本と既存ケースの期待値更新

**Files:**
- Create: `verification/cases/L3-01-broken-logic/{case.patch,expect.yml}`
- Create: `verification/cases/L3-02-openapi-drift/{case.patch,expect.yml}`
- Create: `verification/cases/L3-03-authz-bypass/{case.patch,expect.yml}`
- Modify: `verification/cases/L1-0{1..6}/expect.yml`、`L2-0{2..5}/expect.yml`（計 10 ファイル）

**Interfaces:**
- Consumes: Task 2 の `l3-test`、Task 6 の `l3-openapi-drift`、Task 3 の `findOneForUser`
- Produces: 全 14 ケースが 8 ゲートに対する期待値を持つ

**`claimed_layer` は手順書 §10 の主張そのものなので、実測に合わせて書き換えない。** `expect` の pass/fail は初回実行の実測で確定させる。

### 9-1. 既存 11 ケースの期待値更新

- [ ] **Step 1: `l2-install` で止まるケースを見分ける**

`L2-01-phantom-package` の `expect` は `l2-install: fail` の 1 行だけである。`run-case.sh` は先頭ゲートが失敗すると後続のブロックゲートを実行しないので、後続を書くと `not-run` になって `configVerdict` が `mismatch` になる。**`L2-01` は変更しない。**

- [ ] **Step 2: 残り 10 ケースに 2 行足す**

`L1-01` 〜 `L1-06`、`L2-02` 〜 `L2-05` の `expect.yml` の `expect` ブロック末尾（`l2-gitleaks` の次）に追記する。

```yaml
  l3-test: pass
  l3-openapi-drift: pass
```

**`L2-05-sql-injection` だけは `l3-test` が `fail` になる可能性がある。** このケースは `findByUser` を `$queryRawUnsafe` に置き換えるので、`orders.service.spec.ts`（`findMany` の呼び出し形をアサーションで固定している）と Task 1 の統合テストが落ちる。予想を書かずに Step 3 の実測で確定させる。

- [ ] **Step 3: 更新した 10 ケースを実行して実測で確定させる**

```bash
git add -A && git commit -m "test: 既存ケースに L3 ゲートの期待値を追加"
```

以下をバックグラウンドで実行する（10 ケース × 8 ゲートで 30 分以上かかる）。

```bash
for c in L1-01-eslint-disable-abuse L1-02-explicit-any L1-03-floating-promise \
         L1-04-unused-disable L1-05-unchecked-index L1-06-web-imports-api \
         L2-02-guard-missing L2-03-hardcoded-secret L2-04-new-dependency L2-05-sql-injection; do
  echo "=== $c ==="
  ./verification/run-case.sh "$c"
done
```

各ケースの JSON の `mismatches` を見る。`l3-test` や `l3-openapi-drift` の期待と実測がずれていたら、**`expect` を実測に合わせて更新する**（`claimed_layer` は触らない）。ずれた理由が「そのケースが L3 も赤くする」ことなら、それ自体が記録すべき発見なので findings に書く。

**`claimVerdict` が Phase 2 から変わったケースが 1 つでもあれば退行である。** `RESULTS.md` の現在の判定（✅ 7 / ❌ 4）と突き合わせる。

### 9-2. `L3-01-broken-logic`

- [ ] **Step 4: 欠陥を注入してパッチを作る**

割引率の適用を壊す。`apps/api/src/discount/discount.ts` の最終行を変える。

```ts
  return Math.floor(price * (1 - MEMBER_DISCOUNT_RATE * 2));
```

```bash
mkdir -p verification/cases/L3-01-broken-logic
git diff > verification/cases/L3-01-broken-logic/case.patch
git checkout apps/api/src/discount/discount.ts
```

- [ ] **Step 5: `expect.yml` を書く**

```yaml
id: L3-01-broken-logic
pitfall: 割引計算のロジックを壊す
claimed_layer: L3
# 手順書 §4 は L3（テスト）を回帰の検出に置く。既存の単体テストが
# 割引後の金額を固定しているので、そこで捕まることを主張している。
claimed_gate: l3-test
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: fail
  l3-openapi-drift: pass
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 6: 実行して確認する**

```bash
git add -A && git commit -m "test: L3-01-broken-logic を追加"
./verification/run-case.sh L3-01-broken-logic
```

期待: `claimVerdict: match`、`blockedBy: ["l3-test"]`。実測が違ったら `expect` を実測に合わせ、**なぜ違ったかを findings に書く。**

### 9-3. `L3-02-openapi-drift`

- [ ] **Step 7: 欠陥を注入してパッチを作る**

`OrderResponseDto` に**オプショナルな**項目を 1 つ足す。生成物（`schema.d.ts`）は更新しない。

```ts
  /** 備考。OpenAPI には出るが、既存コードは何も入れない */
  @ApiProperty({ required: false })
  note?: string;
```

**必須プロパティにしないこと。** 必須にすると `toOrderResponse` の戻り値が型を満たさなくなり `l1-typecheck` が fail する。すると「L1 が止めた」になり、このケースが測ろうとしている drift 検出に届かない。オプショナルなら型チェックは通り、OpenAPI のスキーマにだけ差分が出る。

```bash
mkdir -p verification/cases/L3-02-openapi-drift
git diff > verification/cases/L3-02-openapi-drift/case.patch
git checkout apps/api/src/orders/dto/order-response.dto.ts
```

- [ ] **Step 8: `expect.yml` を書く**

```yaml
id: L3-02-openapi-drift
pitfall: DTO を変更して OpenAPI 生成物を更新しない
claimed_layer: L3
# 手順書 §4.4 ③ は「生成物に差分が出たら CI を落とす（＝スキーマ更新漏れの検出）」と
# 明示している。
claimed_gate: l3-openapi-drift
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: pass
  l3-openapi-drift: fail
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 9: 実行して確認する**

```bash
git add -A && git commit -m "test: L3-02-openapi-drift を追加"
./verification/run-case.sh L3-02-openapi-drift
```

期待: `claimVerdict: match`、`blockedBy: ["l3-openapi-drift"]`。

### 9-4. `L3-03-authz-bypass`

- [ ] **Step 10: 欠陥を注入してパッチを作る**

Task 3 の Step 6 で確認した壊し方をそのまま使う。`findOneForUser` の所有者チェックを削る。**`@UseGuards` は付けたまま**にすること（`L2-02-guard-missing` と欠陥の型が重ならないようにするのがこのケースの設計）。

```ts
  async findOneForUser(userId: string, orderId: string): Promise<OrderResponseDto> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { user: true },
    });

    if (order === null) {
      throw new NotFoundException('注文が見つかりません');
    }

    return toOrderResponse(order);
  }
```

`userId` が未使用になると `noUnusedParameters` で `l1-typecheck` が落ちる可能性がある。**その場合はパラメータ名を `_userId` に変えず、`void userId;` の 1 行も足さず、まず実測する。** 落ちたなら「認可を外したら L1 が先に止めた」という結果自体が記録に値する。`expect` を実測に合わせたうえで findings に書く。

```bash
mkdir -p verification/cases/L3-03-authz-bypass
git diff > verification/cases/L3-03-authz-bypass/case.patch
git checkout apps/api/src/orders/orders.service.ts
```

- [ ] **Step 11: `expect.yml` を書く**

```yaml
id: L3-03-authz-bypass
pitfall: 認可チェック（所有者確認）が欠落する
claimed_layer: L2
# 手順書 §10 は「認可チェックの欠落」を L2 / L5 の担当とし、L2 の具体策として
# Semgrep カスタムルールを挙げる。そのカスタムルール（§3.2）は Controller に
# @UseGuards が付いているかしか見ないので、ガードは付いたまま所有者チェックだけが
# 抜けたこのケースには反応しないと予想される。予想どおりなら §10 の割り当てへの
# 反証データになる。claimed_layer は手順書の主張のままにする（絶対に変えない）。
claimed_gate: l2-semgrep
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: fail
  l3-openapi-drift: pass
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 12: 実行して確認する**

```bash
git add -A && git commit -m "test: L3-03-authz-bypass を追加"
./verification/run-case.sh L3-03-authz-bypass
```

**期待は `claimVerdict: mismatch`（❌ 別の層が止めた）である。** これは失敗ではなく、このケースが得ようとしている結果そのものである。`blockedBy` が `["l3-test"]` で `l2-semgrep` が pass なら、手順書 §10 の「認可チェックの欠落 → L2（Semgrep カスタムルール）」がガードの有無しか対象にできていないことの実測データになる。

`l2-semgrep` が fail した場合（カスタムルール以外の 147 ルールのどれかが反応した場合）は、`l2-semgrep.sh` のログを見てどのルール ID が発火したかを確認し、findings に記録する。**申し送り #27（ルール ID 照合）が未解決なので、ここは手で確認するしかない。**

- [ ] **Step 13: コミット**

```bash
git add -A
git commit -m "test: L3 系 3 ケースの期待値を実測で確定"
```

---

## Task 10: 全ケース実行と受け入れ確認

**Files:**
- Modify: `verification/RESULTS.md`（生成物）
- Modify: `docs/superpowers/phase0-findings.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: 作業ツリーをクリーンにして全ケースを実行する**

`run-all.sh` は追跡ファイルである `RESULTS.md` を書き換える。実行前に作業ツリーがクリーンであることを確認する。

```bash
git status --porcelain
```

期待: 空。

14 ケース × 8 ゲート + 対照実行で **1 時間を超える見込み**（Phase 2 の 11 ケース × 7 ゲートで約 40 分 + Testcontainers の起動時間）。Bash ツールのタイムアウト上限を大きく超えるので**必ずバックグラウンドで実行する**。

```bash
./verification/run-all.sh > /tmp/run-all-phase3.log 2>&1
```

- [ ] **Step 2: 対照実行が緑であることを確認する**

ログの先頭（`=== baseline（パッチ無し） ===`）を見る。ここで止まっていたら、パッチ無しの状態でゲートが赤い。ケースの判定は意味を持たないので、先にリポジトリを緑にする。

- [ ] **Step 3: 結果を読む**

```bash
cat verification/RESULTS.md
grep -E '^--- |全体の所要時間' /tmp/run-all-phase3.log
```

確認する点:

1. **L1 系 6 ケースと L2 系 5 ケースの判定が Phase 2 から変わっていないか。** 変わっていたら退行である。原因を突き止めてから先に進む（ただし `L2-04` は Task 8 で ❌ → ✅ に変わるのが正しい）。
2. **L3 系 3 ケースの判定。** `L3-01` と `L3-02` は ✅、`L3-03` は ❌（別の層が止めた）が予想である。
3. **経過時間。** ケース別の秒数から、どのゲートが支配的かを読む。

- [ ] **Step 4: `RESULTS.md` をコミットする**

```bash
git add verification/RESULTS.md
git commit -m "test: 全 14 ケースの検証結果を更新"
```

**コミットするか `git checkout` で戻すかしないと、次回の実行で全行が「⚠️ 実行不能」になる。**

- [ ] **Step 5: findings に Phase 3 の発見をまとめる**

`docs/superpowers/phase0-findings.md` に書く。

§1（手順書への修正提案候補）に足すもの:
- 仮説 8 の結論（Task 1）
- e2e で `ValidationPipe` を再現しないと本番と違う設定で走ること（Task 3）
- 手順書 §4.4 が DTO の `class` 化と `@ApiProperty` に触れていないこと（Task 6）
- drift ゲートが作業ツリーを汚すこと（Task 6）
- 手順書 §4.1 の命名（`*.int-spec.ts`）が Jest の既定 `testMatch` に載らないこと（Task 1）
- 手順書 §4.6 の `--filter='...[origin/main]'` が検証ブランチ上で意味を変えること（Task 2）
- `L3-03` の結果（§10 の「認可チェックの欠落 → L2」への反証データになったかどうか）
- fast-check の `FC_NUM_RUNS` 100 / 10000 の実測時間（Task 5）

§3 に「Phase 4（L4）」の申し送りを追記するもの:
- Phase 3 で新たに増えたゲート 2 本と、Stryker がそれらとどう干渉するか（`l3-test` を 2 回走らせることになる）
- Testcontainers を使うテストがミューテーションテストの実行時間に与える影響（Stryker は各 mutant でテストを回すので、コンテナ起動が mutant ごとに走ると破滅的に遅い。`--selectProjects unit` に絞る等の検討が要る）
- 申し送り #27（ルール ID 照合）は依然として未解決であること
- Task 10 Step 3 で読んだ経過時間の実測値と、Phase 5 で 19 ケースになったときの見込み

§4 に Phase 3 の受け入れ確認記録を追記する。

- [ ] **Step 6: `CLAUDE.md` の「現在地」を更新する**

- Phase 3 完了と、次が Phase 4（L4）であること
- 全 14 ケースの内訳（✅ / ❌ の数）
- **`L2-04` の ❌ に関する注記を削除する**（Task 8 で解消したため）。代わりに `L3-03` の ❌ が「手順書 §10 への反証データであって環境の不具合ではない」ことを書く
- ゲートが 8 本になったこと、`run-all.sh` の所要時間の実測値

- [ ] **Step 7: 全ゲートが緑であることを最終確認する**

```bash
./scripts/gates/gates.test.sh
pnpm turbo typecheck
pnpm lint
shellcheck scripts/gates/*.sh verification/*.sh
node --test verification/lib/judge.test.mjs
```

期待: すべて exit 0。

- [ ] **Step 8: コミットして PR を作る**

```bash
git add -A
git commit -m "docs: Phase 3 の発見と Phase 4 への申し送りを記録"
git push -u origin feat/phase3-l3-tests
```

PR の本文には次を含める。

- Phase 3 で何を足したか（ゲート 2 本、ケース 3 本、アプリ側の追加）
- 仮説 8 の結論
- `RESULTS.md` の判定の変化（Phase 2 との差分）
- `L3-03` が ❌ であることと、それが**意図した結果**であること

**`git push` は forge 側の push protection に阻まれる可能性がある**（§1.28）。`L2-03-hardcoded-secret` の `case.patch` で一度起きている。Phase 3 で新たに秘密らしき文字列を追加していないなら通るはずだが、拒否されたら §1.28 の手順に従う。

---

## Self-Review

計画を書いたあとに spec（設計書 §9・§10、手順書 §4、`phase0-findings.md` §3 の Phase 3 節）と突き合わせた結果。

**1. 手順書 §4 の各節をどのタスクが扱うか**

| 手順書の節 | タスク |
|---|---|
| §4.1 テスト種別の配置 | Task 1（Jest projects）、Task 7（Playwright） |
| §4.2 API：Jest + Testcontainers | Task 1（仮説 8） |
| §4.3 Web：Vitest + Testing Library | 既存（Phase 0 で導入済み）。`l3-test` が `turbo test` 経由で回す（Task 2） |
| §4.4 契約テスト：OpenAPI 型生成 | Task 6 |
| §4.5 プロパティベーステスト：fast-check | Task 5 |
| §4.6 実行コマンド | Task 2（`--filter='...[origin/main]'` を外した理由を含む） |

**2. 設計書の Phase 3 完了条件**

「L3 が緑。L3 系 3 ケースの判定完了。仮説 8 に結論」→ Task 10 Step 7（緑）、Task 9（3 ケース）、Task 1 Step 10（仮説 8）。

**3. `phase0-findings.md` §3 の Phase 3 申し送り 6 件**

| # | 内容 | タスク |
|---|---|---|
| 9 | `AuthGuard` の単体テストが無い | Task 4 |
| 10 | `client.ts` の無検証キャスト | Task 6 Step 5 |
| 11 | Playwright MCP の `.playwright-mcp/`（`.gitignore` 済み） | 対応不要 |
| 12 | FK 違反で 500 | Task 3 |
| 24 | `l1-typecheck` の fail code が tsconfig の形に依存 | Task 6 Step 12（Global Constraints にも記載） |
| 25 | 非ブロックゲートの照合 | Task 8-2 |
| 26 | 実行時間 | Task 8-1 |
| 27 | ルール ID 照合 | **Phase 3 では扱わない**（brainstorming で対象外と決定）。Task 10 Step 5 で Phase 4 へ申し送る |

**4. 型と名前の一貫性**

- `findOneForUser(userId, orderId)` は Task 3 で定義し、Task 9-4 の `case.patch` で同じ名前を使っている
- `detectedBy` / `detectingLayers` は Task 8-2 で `judge.mjs` に足し、同 Step 8 の `run-all.sh` の表示で使っている
- ゲート名は `l3-test` / `l3-openapi-drift` / `l3-e2e-web` の 3 つ。すべて `lN-` で始まる（申し送り #21）
- `GATE_ORDER` は Task 2 で 7 本、Task 6 で 8 本になる。`l3-e2e-web` は入らない（Task 7 Step 8 で確認）

**5. 残る不確実性**

以下は実装時に実測で決める。計画では予想を書かず、実測に合わせて `expect` を更新する方針を明記してある。

- `L2-05-sql-injection` が `l3-test` を赤くするか（Task 9 Step 2）
- `L3-03` で `userId` が未使用になったとき `l1-typecheck` が落ちるか（Task 9 Step 10）
- Jest / Playwright の失敗時サマリの正確な文字列（Task 2 Step 4、Task 7 Step 6 の `gate_fail_if_matches` のパターン）
- `openapi-typescript` 7.13.0 が生成する型のキー構造（Task 6 Step 5 の `OrderView` の導出パス）
