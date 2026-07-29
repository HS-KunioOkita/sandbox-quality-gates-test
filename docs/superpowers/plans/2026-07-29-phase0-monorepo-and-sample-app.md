# Phase 0: モノレポ基盤とサンプルアプリ 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** pnpm workspace + Turborepo のモノレポに NestJS API と React/Vite Web を構築し、`GET /orders` が会員割引を適用した注文一覧を返し、Web がそれを表示する状態にする。

**Architecture:** pnpm workspace（`apps/*` と `packages/*`）を Turborepo で束ねる。API は NestJS 11 + Prisma 6（PostgreSQL）。Web は React 19 + Vite 8。割引ロジックは純関数として `apps/api/src/discount/` に切り出し、閾値などの定数は `packages/shared` から供給する。開発用 PostgreSQL は Docker Compose で立てる。

**Tech Stack:** TypeScript 5.9.3 / NestJS 11.1.28 / Prisma 6.19.3 / React 19.2.8 / Vite 8.1.5 / Jest 30.4.2 + ts-jest 29.4.12 / Vitest 4.1.10 / Turborepo 2.10.7 / pnpm 11.1.1

**設計書:** `docs/superpowers/specs/2026-07-29-multilayer-quality-gates-verification-design.md`

---

## Global Constraints

以下は全タスクに共通して適用される。バージョンは**すべて完全固定（`^` や `~` を付けない）**。検証結果の再現性を担保するため。

### バージョン固定表

| パッケージ | バージョン | 配置 |
|---|---|---|
| `typescript` | `5.9.3` | root（devDependencies） |
| `turbo` | `2.10.7` | root |
| `@types/node` | `26.1.2` | root |
| `@nestjs/common` / `@nestjs/core` / `@nestjs/platform-express` | `11.1.28` | apps/api |
| `@nestjs/testing` | `11.1.28` | apps/api（dev） |
| `reflect-metadata` | `0.2.2` | apps/api |
| `rxjs` | `7.8.2` | apps/api |
| `class-validator` | `0.15.1` | apps/api |
| `class-transformer` | `0.5.1` | apps/api |
| `@prisma/client` | `6.19.3` | apps/api |
| `prisma` | `6.19.3` | apps/api（dev） |
| `jest` | `30.4.2` | apps/api（dev） |
| `ts-jest` | `29.4.12` | apps/api（dev） |
| `@types/jest` | `30.0.0` | apps/api（dev） |
| `ts-node` | `10.9.2` | apps/api（dev） |
| `@types/express` | `5.0.6` | apps/api（dev） |
| `react` / `react-dom` | `19.2.8` | apps/web |
| `@types/react` | `19.2.17` | apps/web（dev） |
| `@types/react-dom` | `19.2.3` | apps/web（dev） |
| `vite` | `8.1.5` | apps/web（dev） |
| `@vitejs/plugin-react` | `6.0.4` | apps/web（dev） |
| `vitest` | `4.1.10` | apps/web（dev） |
| `@vitest/coverage-v8` | `4.1.10` | apps/web（dev） |
| `@testing-library/react` | `16.3.2` | apps/web（dev） |
| `@testing-library/jest-dom` | `7.0.0` | apps/web（dev） |
| `jsdom` | `30.0.0` | apps/web（dev） |

### TypeScript を 5.9.3 に固定する理由（重要）

最新は **7.0.2** だが使用できない。以下の 2 つの上限に挟まれる。

- `ts-jest@29.4.12` の peerDependency: `typescript: ">=4.3 <7"`
- `typescript-eslint@8.65.0` の peerDependency: `typescript: ">=4.8.4 <6.1.0"`

交差は `<6.1.0`、すなわち上限 6.0.x。6.0 系は移行期リリースでデコレータ周りの実績が乏しいため、NestJS 11 + ts-jest 29 で実績のある **5.9.3** を採用する。手順書はこの制約に言及していないため、**Phase 6 の検証レポートに「手順書は TypeScript バージョン制約に触れていない」として記録する**。

### Prisma を 6.19.3 に固定する理由（重要）

最新は **7.9.1** だが採用しない。Prisma 7 は `prisma-client` ジェネレータが**生成物を TypeScript ソースとしてリポジトリ内**（`output` で指定したパス）に出力するため、以下が起きる。

- 生成コードが L1（`tsc --noEmit` / ESLint）の対象になる
- 生成コードが L4（Stryker の `mutate`）の対象になる

これは検証したいゲート本来の挙動にノイズを持ち込む。Prisma 6 の `prisma-client-js` ジェネレータは `node_modules/.prisma/client` にコンパイル済み JS + `.d.ts` を出力するため、ゲートの視界に入らない。**Prisma は本検証における付随的なインフラであり、無関係なリスクを最小化する版を選ぶ。**

なお「Prisma 7 に上げると生成コードがゲート対象になる」ことは、手順書 §5.2 の「生成コードを除外せよ」という規定の実地検証テーマとして有用なので、**Phase 6 の検証レポートに追加検証候補として記録する**。

### 命名・記述ルール

- ワークスペースパッケージ名の接頭辞は `@repo/`（手順書 §2.2 の `@repo/tsconfig` に合わせる）。
- ワークスペース間依存は `"workspace:*"` で記述する。
- コード内コメントと例外メッセージは日本語で書く。
- **`packages/shared` から Web 側へは型のみを import する**（`import type`）。Web は Vite（ESM）、API は NestJS（CommonJS）で、`packages/shared` は CommonJS を出力するため。型のみの import はコンパイル時に消えるので実行時の形式差が問題にならない。将来 Web が実行時に定数を必要とした場合の保険として `vite.config.ts` に `optimizeDeps.include: ['@repo/shared']` を入れておく。

### tsconfig の扱い

`packages/tsconfig/base.json` は**手順書 §2.1 の内容をそのまま Phase 0 で作成する**（strict + 追加フラグ全部）。

設計書の Phase 1 は「tsconfig 厳格化 + ESLint」となっているが、厳格な設定に後から合わせるより最初から厳格な設定で書くほうが手戻りが少ない。**この結果 Phase 1 の作業は ESLint 導入 + ゲートスクリプト + 検証ハーネスに絞られる。** L1 の検証ケース（特に `L1-05-unchecked-index`）は `noUncheckedIndexedAccess` が実際に効くことを検証するので、検証価値は落ちない。

なお手順書 §2.1 の注記どおり `exactOptionalPropertyTypes` は**入れない**。

---

## File Structure

Phase 0 で作成するファイルと責務。

### ルート

| ファイル | 責務 |
|---|---|
| `package.json` | ワークスペースルート。turbo / typescript を devDependencies に持ち、`build`/`typecheck`/`test` を turbo に委譲 |
| `pnpm-workspace.yaml` | `apps/*` と `packages/*` をワークスペースに登録 |
| `turbo.json` | `build` / `typecheck` / `test` タスクの依存関係と出力を定義 |
| `.gitignore` | `node_modules` / `dist` / `.env` / `coverage` / `.turbo` を除外 |
| `docker-compose.yml` | 開発用 PostgreSQL 16 |
| `.env.example` | `DATABASE_URL` の雛形（`.env` は git 管理外） |

### packages/

| ファイル | 責務 |
|---|---|
| `packages/tsconfig/package.json` | `@repo/tsconfig`。設定ファイルを配るだけのパッケージ |
| `packages/tsconfig/base.json` | 手順書 §2.1 の共通 compilerOptions |
| `packages/shared/package.json` | `@repo/shared`。CommonJS + `.d.ts` を `dist/` に出力 |
| `packages/shared/tsconfig.json` | base.json を extends し `dist` へ出力 |
| `packages/shared/src/index.ts` | 割引ポリシー定数と `OrderStatus` 型。API・Web の双方が参照する唯一の共有点 |

### apps/api/

| ファイル | 責務 |
|---|---|
| `package.json` | 依存とスクリプト（`build`/`typecheck`/`test`/`start:dev`/`db:migrate`/`db:seed`） |
| `tsconfig.json` | 手順書 §2.2。typecheck 用（`noEmit`）と IDE 用 |
| `tsconfig.build.json` | `dist` 出力用。テストファイルを除外 |
| `tsconfig.spec.json` | ts-jest 用。`noUnusedLocals` を緩める |
| `jest.config.ts` | Jest 設定。手順書 §5.2 の Stryker が参照するファイル名に合わせる |
| `prisma/schema.prisma` | `User` / `Order` / `OrderStatus` のデータモデル |
| `prisma/seed.ts` | 会員 1 名・非会員 1 名と注文数件を投入 |
| `src/main.ts` | アプリ起動。CORS 許可と `ValidationPipe` の適用 |
| `src/app.module.ts` | ルートモジュール |
| `src/prisma/prisma.service.ts` | `PrismaClient` を DI に載せる。接続/切断のライフサイクル管理 |
| `src/prisma/prisma.module.ts` | `PrismaService` を提供・エクスポート |
| `src/discount/discount.ts` | `applyDiscount` 純関数。L4 とプロパティベーステストの主戦場 |
| `src/discount/discount.spec.ts` | `applyDiscount` の境界値テスト |
| `src/auth/auth.guard.ts` | `x-user-id` ヘッダを読み `request.userId` に載せる |
| `src/orders/dto/create-order.dto.ts` | POST の入力 DTO。class-validator で検証 |
| `src/orders/dto/order-response.dto.ts` | レスポンス型。Phase 3 で `@ApiProperty` を足す土台 |
| `src/orders/orders.service.ts` | Prisma で注文を読み書きし割引を適用 |
| `src/orders/orders.service.spec.ts` | `OrdersService` のユニットテスト（Prisma はモック） |
| `src/orders/orders.controller.ts` | `GET /orders` / `POST /orders`。`AuthGuard` を適用 |
| `src/orders/orders.module.ts` | orders 機能のモジュール |

### apps/web/

| ファイル | 責務 |
|---|---|
| `package.json` | 依存とスクリプト |
| `tsconfig.json` | 手順書 §2.3。`src` と `e2e` を対象 |
| `tsconfig.node.json` | `vite.config.ts` / `vitest.config.ts` 用 |
| `vite.config.ts` | React プラグイン、dev サーバのポート |
| `vitest.config.ts` | 手順書 §4.3。jsdom + setup + v8 カバレッジ |
| `index.html` | Vite のエントリ HTML |
| `src/env.d.ts` | `import.meta.env` の型定義 |
| `src/main.tsx` | React のマウント |
| `src/App.tsx` | ルートコンポーネント。ユーザー切り替えと `OrderList` の配置 |
| `src/api/client.ts` | `OrderView` 型と `fetchOrders`。Phase 3 で生成型に差し替える境界 |
| `src/features/orders/orderTotal.ts` | 合計計算と割引適用判定。Stryker（Vitest ランナー）の対象 |
| `src/features/orders/orderTotal.test.ts` | 上記のユニットテスト |
| `src/features/orders/OrderList.tsx` | 注文一覧の表示。読み込み中・エラー・空・データありの 4 状態 |
| `src/features/orders/OrderList.test.tsx` | 上記のコンポーネントテスト |
| `src/test/setup.ts` | `@testing-library/jest-dom` の登録 |

---

## Task 1: モノレポ基盤と開発用 PostgreSQL

**Files:**
- Create: `package.json`
- Create: `pnpm-workspace.yaml`
- Create: `turbo.json`
- Create: `.gitignore`
- Create: `docker-compose.yml`
- Create: `.env.example`
- Create: `packages/tsconfig/package.json`
- Create: `packages/tsconfig/base.json`

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces:
  - ワークスペース名 `@repo/tsconfig`。他パッケージは `"extends": "@repo/tsconfig/base.json"` で参照する
  - turbo タスク名 `build` / `typecheck` / `test`
  - 環境変数 `DATABASE_URL`（形式: `postgresql://postgres:postgres@localhost:5432/quality_gates?schema=public`）

- [ ] **Step 1: `pnpm-workspace.yaml` を作成**

```yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

- [ ] **Step 2: ルート `package.json` を作成**

`private: true` は必須（ワークスペースルートは公開しない）。バージョンは完全固定で `^` を付けない。

```json
{
  "name": "sandbox-quality-gates-test",
  "version": "0.0.0",
  "private": true,
  "packageManager": "pnpm@11.1.1",
  "scripts": {
    "build": "turbo build",
    "typecheck": "turbo typecheck",
    "test": "turbo test",
    "db:up": "docker compose up -d",
    "db:down": "docker compose down"
  },
  "devDependencies": {
    "@types/node": "26.1.2",
    "turbo": "2.10.7",
    "typescript": "5.9.3"
  }
}
```

- [ ] **Step 3: `turbo.json` を作成**

手順書 §1.2 の内容に `outputs` を補う。`"tasks"` キーは Turborepo 2.x の書式（1.x は `"pipeline"`）。

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "typecheck": { "dependsOn": ["^build"] },
    "lint": {},
    "test": { "dependsOn": ["^build"], "outputs": ["coverage/**"] },
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] }
  }
}
```

- [ ] **Step 4: `.gitignore` を作成**

既に `.gitignore` が存在する場合は、この内容で上書きする。

```gitignore
node_modules/
dist/
coverage/
.turbo/
.env
reports/
openapi.json
.superpowers/
```

`reports/` は Stryker の incremental ファイル（手順書 §5.2）、`openapi.json` は Phase 3 の生成物。Phase 0 では未使用だが、後で追記漏れを起こさないよう先に入れる。`.superpowers/` は superpowers スキルの作業用スクラッチ領域。

- [ ] **Step 5: `docker-compose.yml` を作成**

設計書の完了条件「API が `GET /orders` を返す」を満たすには実 PostgreSQL が必要。設計書にはこのファイルの記載がないが、Phase 0 の完了条件を満たすために必須なので追加する。

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: quality-gates-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: quality_gates
    ports:
      - '5432:5432'
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U postgres -d quality_gates']
      interval: 5s
      timeout: 5s
      retries: 10
```

- [ ] **Step 6: `.env.example` を作成**

```bash
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/quality_gates?schema=public"
```

- [ ] **Step 7: `packages/tsconfig/package.json` を作成**

```json
{
  "name": "@repo/tsconfig",
  "version": "0.0.0",
  "private": true,
  "files": ["base.json"]
}
```

- [ ] **Step 8: `packages/tsconfig/base.json` を作成**

手順書 §2.1 のとおり。`exactOptionalPropertyTypes` は同節の注記に従い入れない。

```json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

- [ ] **Step 9: 依存をインストールして turbo が動くことを確認**

```bash
pnpm install
pnpm turbo --version
```

Expected: `pnpm install` が成功し、`pnpm turbo --version` が `2.10.7` を出力する。

- [ ] **Step 10: PostgreSQL が起動して接続できることを確認**

```bash
cp .env.example .env
pnpm db:up
docker compose exec -T postgres pg_isready -U postgres -d quality_gates
```

Expected: 最後のコマンドが `/var/run/postgresql:5432 - accepting connections` を出力し exit 0。

もし `pg_isready` が失敗する場合は起動待ちが足りないので、10 秒待って再実行する。

- [ ] **Step 11: コミット**

```bash
git add package.json pnpm-workspace.yaml turbo.json .gitignore docker-compose.yml .env.example packages/tsconfig pnpm-lock.yaml
git commit -m "feat: pnpm workspace + Turborepo 基盤と開発用 PostgreSQL を追加"
```

---

## Task 2: 共有パッケージと割引ドメイン（TDD）

**Files:**
- Create: `packages/shared/package.json`
- Create: `packages/shared/tsconfig.json`
- Create: `packages/shared/src/index.ts`
- Create: `apps/api/package.json`
- Create: `apps/api/tsconfig.json`
- Create: `apps/api/tsconfig.build.json`
- Create: `apps/api/tsconfig.spec.json`
- Create: `apps/api/jest.config.ts`
- Test: `apps/api/src/discount/discount.spec.ts`
- Create: `apps/api/src/discount/discount.ts`

**Interfaces:**
- Consumes: `@repo/tsconfig/base.json`（Task 1）、turbo タスク名 `build` / `typecheck` / `test`（Task 1）
- Produces:
  - `@repo/shared` から `MEMBER_DISCOUNT_RATE: number`（値 `0.1`）、`MEMBER_DISCOUNT_MIN_PRICE: number`（値 `1000`）、`type OrderStatus = 'PENDING' | 'PAID' | 'CANCELLED'`
  - `apps/api/src/discount/discount.ts` から `applyDiscount(price: number, isMember: boolean): number`
  - `apps/api` のパッケージ名は `api`（手順書 §4.2 の `pnpm add -D --filter api` に合わせる）

- [ ] **Step 1: `packages/shared/package.json` を作成**

CommonJS を出力する。Web 側は型のみ import するので実行時形式は問題にならない。

```json
{
  "name": "@repo/shared",
  "version": "0.0.0",
  "private": true,
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "typecheck": "tsc -p tsconfig.json --noEmit"
  },
  "devDependencies": {
    "@repo/tsconfig": "workspace:*"
  }
}
```

- [ ] **Step 2: `packages/shared/tsconfig.json` を作成**

```json
{
  "extends": "@repo/tsconfig/base.json",
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "moduleResolution": "node10",
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "include": ["src/**/*.ts"]
}
```

- [ ] **Step 3: `packages/shared/src/index.ts` を作成**

割引の閾値をここに置く理由は 2 つ。API と Web が同じ値を参照する必要があること、そして `MEMBER_DISCOUNT_MIN_PRICE` が後の検証ケース `L4-02-off-by-one-fixed-by-test` の境界値になることである。

```ts
/** 会員割引率（10%） */
export const MEMBER_DISCOUNT_RATE = 0.1;

/** 会員割引が適用される最低金額。この金額以上のときに割引する */
export const MEMBER_DISCOUNT_MIN_PRICE = 1000;

/** 注文のステータス */
export type OrderStatus = 'PENDING' | 'PAID' | 'CANCELLED';
```

- [ ] **Step 4: `@repo/shared` をビルドできることを確認**

```bash
pnpm install
pnpm --filter @repo/shared build
ls packages/shared/dist
```

Expected: `index.js` と `index.d.ts` が生成される。

- [ ] **Step 5: `apps/api/package.json` を作成**

パッケージ名は `api`（`@repo/api` ではない）。手順書が `--filter api` と書いているため。

```json
{
  "name": "api",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "typecheck": "tsc -p tsconfig.json --noEmit",
    "test": "jest",
    "start:dev": "ts-node -P tsconfig.build.json src/main.ts",
    "db:migrate": "prisma migrate dev",
    "db:seed": "ts-node -P tsconfig.build.json prisma/seed.ts"
  },
  "dependencies": {
    "@nestjs/common": "11.1.28",
    "@nestjs/core": "11.1.28",
    "@nestjs/platform-express": "11.1.28",
    "@prisma/client": "6.19.3",
    "@repo/shared": "workspace:*",
    "class-transformer": "0.5.1",
    "class-validator": "0.15.1",
    "reflect-metadata": "0.2.2",
    "rxjs": "7.8.2"
  },
  "devDependencies": {
    "@nestjs/testing": "11.1.28",
    "@repo/tsconfig": "workspace:*",
    "@types/express": "5.0.6",
    "@types/jest": "30.0.0",
    "jest": "30.4.2",
    "prisma": "6.19.3",
    "ts-jest": "29.4.12",
    "ts-node": "10.9.2"
  }
}
```

`ts-node` を入れる理由は 2 つ。`jest.config.ts` を TypeScript で書くため（手順書 §1.1 のファイル名と §5.2 の `"configFile": "jest.config.ts"` に合わせる）、および `prisma/seed.ts` を実行するため。

- [ ] **Step 6: `apps/api/tsconfig.json` を作成**

手順書 §2.2 のとおり。`strictPropertyInitialization: false` は DI・Entity のプロパティに `!` を大量付与するのを避けるため。

```json
{
  "extends": "@repo/tsconfig/base.json",
  "compilerOptions": {
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "strictPropertyInitialization": false,
    "target": "ES2022",
    "module": "commonjs",
    "moduleResolution": "node10",
    "outDir": "./dist",
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "types": ["node", "jest"]
  },
  "include": ["src/**/*.ts", "test/**/*.ts", "prisma/**/*.ts", "jest.config.ts"]
}
```

- [ ] **Step 7: `apps/api/tsconfig.build.json` を作成**

`dist` 出力用。テストと設定ファイルを除外する。

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "types": ["node"]
  },
  "include": ["src/**/*.ts"],
  "exclude": ["src/**/*.spec.ts"]
}
```

- [ ] **Step 8: `apps/api/tsconfig.spec.json` を作成**

ts-jest 用。テストコードでは未使用変数が一時的に出やすいので `noUnusedLocals` / `noUnusedParameters` を緩める。**本体コードには適用されない**ので L1 の厳格さは損なわれない。

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "noUnusedLocals": false,
    "noUnusedParameters": false
  }
}
```

- [ ] **Step 9: `apps/api/jest.config.ts` を作成**

`collectCoverageFrom` の除外は手順書 §5.2 の `mutate` 設定と同じ方針（`*.module.ts`・エントリポイントを除く）に揃える。

```ts
import type { Config } from 'jest';

const config: Config = {
  rootDir: '.',
  testEnvironment: 'node',
  testMatch: ['<rootDir>/src/**/*.spec.ts', '<rootDir>/test/**/*.spec.ts'],
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/tsconfig.spec.json' }],
  },
  moduleFileExtensions: ['ts', 'js', 'json'],
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.spec.ts',
    '!src/main.ts',
    '!src/**/*.module.ts',
  ],
  coverageDirectory: 'coverage',
};

export default config;
```

- [ ] **Step 10: 失敗するテストを書く**

`apps/api/src/discount/discount.spec.ts`:

```ts
import { MEMBER_DISCOUNT_MIN_PRICE } from '@repo/shared';
import { applyDiscount } from './discount';

describe('applyDiscount', () => {
  it('非会員は割引されない', () => {
    expect(applyDiscount(2000, false)).toBe(2000);
  });

  it('会員で閾値ちょうどのときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE, true)).toBe(900);
  });

  it('会員で閾値のすぐ下のときは割引されない', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE - 1, true)).toBe(999);
  });

  it('会員で閾値のすぐ上のときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE + 1, true)).toBe(900);
  });

  it('割引後の端数は切り捨てる', () => {
    // 1005 * 0.9 = 904.5 → 904
    expect(applyDiscount(1005, true)).toBe(904);
  });

  it('0 円は割引されない', () => {
    expect(applyDiscount(0, true)).toBe(0);
  });
});
```

閾値の「ちょうど・すぐ下・すぐ上」を明示的に書いているのは、手順書 §6.2 のチェックリスト最初の項目（境界値）に対応させるため。

- [ ] **Step 11: テストが失敗することを確認**

```bash
pnpm install
pnpm --filter @repo/shared build
pnpm --filter api test
```

Expected: FAIL。`Cannot find module './discount'` というエラーになる。

- [ ] **Step 12: 最小の実装を書く**

`apps/api/src/discount/discount.ts`:

```ts
import { MEMBER_DISCOUNT_MIN_PRICE, MEMBER_DISCOUNT_RATE } from '@repo/shared';

/**
 * 会員割引を適用した価格を返す。
 *
 * 会員であり、かつ price が MEMBER_DISCOUNT_MIN_PRICE 以上のときだけ割引する。
 * 割引後の端数は切り捨てる。
 */
export function applyDiscount(price: number, isMember: boolean): number {
  if (!isMember) {
    return price;
  }
  if (price < MEMBER_DISCOUNT_MIN_PRICE) {
    return price;
  }
  return Math.floor(price * (1 - MEMBER_DISCOUNT_RATE));
}
```

- [ ] **Step 13: テストが通ることを確認**

```bash
pnpm --filter api test
```

Expected: PASS。6 件すべて成功。

- [ ] **Step 14: typecheck が通ることを確認**

```bash
pnpm --filter api typecheck
pnpm --filter @repo/shared typecheck
```

Expected: どちらも出力なしで exit 0。

- [ ] **Step 15: コミット**

```bash
git add packages/shared apps/api pnpm-lock.yaml
git commit -m "feat: 共有定数パッケージと割引ドメイン（applyDiscount）を追加"
```

---

## Task 3: Prisma スキーマ・マイグレーション・シード

**Files:**
- Create: `apps/api/prisma/schema.prisma`
- Create: `apps/api/prisma/seed.ts`
- Create: `apps/api/.env`（git 管理外）
- Modify: `.gitignore`（既に `.env` を含むので変更不要。確認のみ）

**Interfaces:**
- Consumes: `DATABASE_URL`（Task 1）、`OrderStatus` 型の値集合（Task 2 の `@repo/shared`）
- Produces:
  - Prisma モデル `User { id, email, name, isMember, orders }` と `Order { id, userId, user, productName, unitPrice, quantity, status, createdAt }`
  - Prisma enum `OrderStatus { PENDING, PAID, CANCELLED }`（`@repo/shared` の `OrderStatus` 型と同じ値集合）
  - `@prisma/client` から `PrismaClient` / `Order` / `User` 型が使えるようになる
  - シード後のデータ: 会員 `member@example.com`（注文 2 件）、非会員 `guest@example.com`（注文 1 件）

- [ ] **Step 1: `apps/api/prisma/schema.prisma` を作成**

`provider = "prisma-client-js"` を明示する。これが Prisma 6 の既定であり、生成物が `node_modules/.prisma/client` に出るためゲートの視界に入らない（Global Constraints 参照）。

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum OrderStatus {
  PENDING
  PAID
  CANCELLED
}

model User {
  id       String  @id @default(uuid())
  email    String  @unique
  name     String
  isMember Boolean @default(false)
  orders   Order[]
}

model Order {
  id          String      @id @default(uuid())
  userId      String
  user        User        @relation(fields: [userId], references: [id])
  productName String
  unitPrice   Int
  quantity    Int
  status      OrderStatus @default(PENDING)
  createdAt   DateTime    @default(now())

  @@index([userId])
}
```

`@@index([userId])` を入れているのは、`GET /orders` が `where: { userId }` で検索するため。

- [ ] **Step 2: `apps/api/.env` を作成**

Prisma CLI はコマンドを実行するディレクトリの `.env` を読む。ルートの `.env` とは別に `apps/api/.env` が必要。

```bash
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/quality_gates?schema=public"
```

- [ ] **Step 3: PostgreSQL が起動していることを確認し、マイグレーションを作成**

```bash
pnpm db:up
docker compose exec -T postgres pg_isready -U postgres -d quality_gates
pnpm --filter api exec prisma migrate dev --name init
```

Expected: `apps/api/prisma/migrations/<timestamp>_init/migration.sql` が生成され、`Your database is now in sync with your schema.` と表示される。Prisma Client の生成も同時に走る。

- [ ] **Step 4: テーブルが作られたことを確認**

```bash
docker compose exec -T postgres psql -U postgres -d quality_gates -c '\dt'
```

Expected: `User` / `Order` / `_prisma_migrations` の 3 テーブルが一覧に出る。

- [ ] **Step 5: シードスクリプトを書く**

`apps/api/prisma/seed.ts`:

会員と非会員を作り分けるのは、`GET /orders` の割引適用差を目視確認できるようにするため。金額は割引閾値（1000 円）の上・下を意図的に混ぜている。

```ts
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main(): Promise<void> {
  // 冪等にするため既存データを消してから投入する
  await prisma.order.deleteMany();
  await prisma.user.deleteMany();

  const member = await prisma.user.create({
    data: {
      email: 'member@example.com',
      name: '会員ユーザー',
      isMember: true,
      orders: {
        create: [
          // 1200 * 1 = 1200 → 閾値以上なので割引され 1080
          { productName: 'キーボード', unitPrice: 1200, quantity: 1, status: 'PAID' },
          // 300 * 2 = 600 → 閾値未満なので割引されず 600
          { productName: 'ケーブル', unitPrice: 300, quantity: 2, status: 'PENDING' },
        ],
      },
    },
  });

  const guest = await prisma.user.create({
    data: {
      email: 'guest@example.com',
      name: '非会員ユーザー',
      isMember: false,
      orders: {
        // 非会員なので 5000 でも割引されない
        create: [{ productName: 'モニター', unitPrice: 5000, quantity: 1, status: 'PAID' }],
      },
    },
  });

  console.info(`投入完了: member=${member.id} guest=${guest.id}`);
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => {
    void prisma.$disconnect();
  });
```

`console.info` / `console.error` を使っているが、手順書 §2.4 の ESLint 設定には `no-console: 'error'` がある。**Phase 1 で ESLint を導入するとこのファイルが引っかかる。** そのときは `eslint.config.js` で `prisma/seed.ts` を対象外にするか、`require-description` 付きの `eslint-disable-next-line` を書く。どちらが適切かは Phase 1 で判断する。

- [ ] **Step 6: シードを実行**

```bash
pnpm --filter api run db:seed
```

Expected: `投入完了: member=<uuid> guest=<uuid>` と表示される。

- [ ] **Step 7: データが入ったことを確認**

```bash
docker compose exec -T postgres psql -U postgres -d quality_gates \
  -c 'SELECT u.name, u."isMember", o."productName", o."unitPrice", o.quantity FROM "Order" o JOIN "User" u ON u.id = o."userId" ORDER BY u.name;'
```

Expected: 3 行返る。会員ユーザー 2 行（キーボード 1200×1、ケーブル 300×2）、非会員ユーザー 1 行（モニター 5000×1）。

- [ ] **Step 8: `.env` が git 管理外であることを確認**

```bash
git status --porcelain apps/api/.env
```

Expected: 出力なし（`.gitignore` の `.env` パターンで除外されている）。もし出力があれば `.gitignore` に `.env` が効いていないので修正する。

- [ ] **Step 9: コミット**

```bash
git add apps/api/prisma
git commit -m "feat: Prisma スキーマ・初期マイグレーション・シードを追加"
```

---

## Task 4: PrismaService と OrdersService（TDD）

**Files:**
- Create: `apps/api/src/prisma/prisma.service.ts`
- Create: `apps/api/src/prisma/prisma.module.ts`
- Create: `apps/api/src/orders/dto/order-response.dto.ts`
- Test: `apps/api/src/orders/orders.service.spec.ts`
- Create: `apps/api/src/orders/orders.service.ts`

**Interfaces:**
- Consumes: `applyDiscount(price: number, isMember: boolean): number`（Task 2）、`PrismaClient` と Prisma モデル型（Task 3）、`OrderStatus`（Task 2）
- Produces:
  - `PrismaService extends PrismaClient`（`@Injectable()`、`onModuleInit` / `onModuleDestroy` を実装）
  - `PrismaModule`（`PrismaService` を providers と exports に持つ）
  - `interface OrderResponseDto { id: string; productName: string; unitPrice: number; quantity: number; status: OrderStatus; discountedTotal: number }`
  - `OrdersService` のメソッド:
    - `findByUser(userId: string): Promise<OrderResponseDto[]>`
    - `create(userId: string, dto: CreateOrderDto): Promise<OrderResponseDto>` ※ `CreateOrderDto` は Task 5 で定義するため、本タスクでは `create` は実装しない
  - `OrdersService` のコンストラクタ引数は `(private readonly prisma: PrismaService)`

**注記:** `create` は入力 DTO（Task 5）に依存するため Task 5 で追加する。本タスクは `findByUser` のみを実装する。

- [ ] **Step 1: `apps/api/src/prisma/prisma.service.ts` を作成**

`onModuleInit` / `onModuleDestroy` はインタフェースの実装であり基底クラスのメソッドの上書きではないので、`noImplicitOverride: true` でも `override` キーワードは不要。

```ts
import { Injectable, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
```

- [ ] **Step 2: `apps/api/src/prisma/prisma.module.ts` を作成**

```ts
import { Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

- [ ] **Step 3: `apps/api/src/orders/dto/order-response.dto.ts` を作成**

Phase 3 で `@nestjs/swagger` の `@ApiProperty` を足してクラスに変える。Phase 0 では interface で十分。

```ts
import type { OrderStatus } from '@repo/shared';

/** 注文一覧・注文作成のレスポンス */
export interface OrderResponseDto {
  id: string;
  productName: string;
  unitPrice: number;
  quantity: number;
  status: OrderStatus;
  /** 会員割引を適用した合計金額 */
  discountedTotal: number;
}
```

- [ ] **Step 4: 失敗するテストを書く**

`apps/api/src/orders/orders.service.spec.ts`:

Prisma はモックする。`include: { user: true }` を指定していることをテストで固定するのは、後の検証ケース `L5-02-n-plus-one` が「この `include` を外して 1 件ずつ引く」形で N+1 を作り込むため。ここを固定しておくと、N+1 の混入が L3 で捕まるのか L5 でしか捕まらないのかを切り分けられる。

```ts
import { Test } from '@nestjs/testing';
import { PrismaService } from '../prisma/prisma.service';
import { OrdersService } from './orders.service';

interface MockPrisma {
  order: {
    findMany: jest.Mock;
  };
}

function createMockPrisma(): MockPrisma {
  return { order: { findMany: jest.fn() } };
}

describe('OrdersService', () => {
  let service: OrdersService;
  let prisma: MockPrisma;

  beforeEach(async () => {
    prisma = createMockPrisma();
    const moduleRef = await Test.createTestingModule({
      providers: [OrdersService, { provide: PrismaService, useValue: prisma }],
    }).compile();
    service = moduleRef.get(OrdersService);
  });

  describe('findByUser', () => {
    it('会員の注文には割引を適用した合計を返す', async () => {
      prisma.order.findMany.mockResolvedValue([
        {
          id: 'order-1',
          productName: 'キーボード',
          unitPrice: 1200,
          quantity: 1,
          status: 'PAID',
          user: { isMember: true },
        },
      ]);

      const result = await service.findByUser('user-1');

      // 1200 * 1 = 1200 → 会員かつ閾値以上なので 1080
      expect(result).toEqual([
        {
          id: 'order-1',
          productName: 'キーボード',
          unitPrice: 1200,
          quantity: 1,
          status: 'PAID',
          discountedTotal: 1080,
        },
      ]);
    });

    it('非会員の注文には割引を適用しない', async () => {
      prisma.order.findMany.mockResolvedValue([
        {
          id: 'order-2',
          productName: 'モニター',
          unitPrice: 5000,
          quantity: 1,
          status: 'PAID',
          user: { isMember: false },
        },
      ]);

      const result = await service.findByUser('user-2');

      expect(result[0]?.discountedTotal).toBe(5000);
    });

    it('単価×数量の合計に対して割引を判定する', async () => {
      prisma.order.findMany.mockResolvedValue([
        {
          id: 'order-3',
          productName: 'ケーブル',
          unitPrice: 300,
          quantity: 2,
          status: 'PENDING',
          user: { isMember: true },
        },
      ]);

      const result = await service.findByUser('user-1');

      // 300 * 2 = 600 → 閾値 1000 未満なので割引されない
      expect(result[0]?.discountedTotal).toBe(600);
    });

    it('指定ユーザーで絞り込み、user を同時に取得する（N+1 を避ける）', async () => {
      prisma.order.findMany.mockResolvedValue([]);

      await service.findByUser('user-1');

      expect(prisma.order.findMany).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        include: { user: true },
        orderBy: { createdAt: 'desc' },
      });
    });

    it('注文が無いときは空配列を返す', async () => {
      prisma.order.findMany.mockResolvedValue([]);

      await expect(service.findByUser('user-1')).resolves.toEqual([]);
    });
  });
});
```

- [ ] **Step 5: テストが失敗することを確認**

```bash
pnpm --filter api test src/orders/orders.service.spec.ts
```

Expected: FAIL。`Cannot find module './orders.service'` というエラーになる。

- [ ] **Step 6: 最小の実装を書く**

`apps/api/src/orders/orders.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { applyDiscount } from '../discount/discount';
import { PrismaService } from '../prisma/prisma.service';
import type { OrderResponseDto } from './dto/order-response.dto';

@Injectable()
export class OrdersService {
  constructor(private readonly prisma: PrismaService) {}

  /** 指定ユーザーの注文一覧を、会員割引を適用した合計付きで返す */
  async findByUser(userId: string): Promise<OrderResponseDto[]> {
    const orders = await this.prisma.order.findMany({
      where: { userId },
      include: { user: true },
      orderBy: { createdAt: 'desc' },
    });

    return orders.map((order) => ({
      id: order.id,
      productName: order.productName,
      unitPrice: order.unitPrice,
      quantity: order.quantity,
      status: order.status,
      discountedTotal: applyDiscount(order.unitPrice * order.quantity, order.user.isMember),
    }));
  }
}
```

- [ ] **Step 7: テストが通ることを確認**

```bash
pnpm --filter api test
```

Expected: PASS。`discount.spec.ts` の 6 件と `orders.service.spec.ts` の 5 件、合計 11 件成功。

- [ ] **Step 8: typecheck が通ることを確認**

```bash
pnpm --filter api typecheck
```

Expected: 出力なしで exit 0。

- [ ] **Step 9: コミット**

```bash
git add apps/api/src
git commit -m "feat: PrismaService と OrdersService.findByUser を追加"
```

---

## Task 5: AuthGuard・OrdersController・アプリ起動

**Files:**
- Create: `apps/api/src/auth/auth.guard.ts`
- Create: `apps/api/src/orders/dto/create-order.dto.ts`
- Modify: `apps/api/src/orders/orders.service.ts`（`create` メソッドを追加）
- Modify: `apps/api/src/orders/orders.service.spec.ts`（`create` のテストを追加）
- Create: `apps/api/src/orders/orders.controller.ts`
- Create: `apps/api/src/orders/orders.module.ts`
- Create: `apps/api/src/app.module.ts`
- Create: `apps/api/src/main.ts`

**Interfaces:**
- Consumes: `OrdersService.findByUser`（Task 4）、`PrismaModule` / `PrismaService`（Task 4）、`OrderResponseDto`（Task 4）
- Produces:
  - `interface AuthenticatedRequest extends Request { userId: string }`（`auth.guard.ts` から export）
  - `AuthGuard implements CanActivate`（`canActivate(context: ExecutionContext): boolean`）
  - `class CreateOrderDto { productName: string; unitPrice: number; quantity: number }`
  - `OrdersService.create(userId: string, dto: CreateOrderDto): Promise<OrderResponseDto>`
  - `OrdersController`（`GET /orders` と `POST /orders`）
  - `AppModule`
  - API は `http://localhost:3000` で待ち受ける

- [ ] **Step 1: `apps/api/src/auth/auth.guard.ts` を作成**

認証は `x-user-id` ヘッダを読むだけの最小実装にする。設計書の非目標にあるとおり、検証対象は認可であって認証機構ではない。

```ts
import {
  type CanActivate,
  type ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';

/** AuthGuard が userId を載せたあとのリクエスト */
export interface AuthenticatedRequest extends Request {
  userId: string;
}

@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const userId = request.headers['x-user-id'];

    if (typeof userId !== 'string' || userId.length === 0) {
      throw new UnauthorizedException('x-user-id ヘッダが必要です');
    }

    request.userId = userId;
    return true;
  }
}
```

- [ ] **Step 2: `apps/api/src/orders/dto/create-order.dto.ts` を作成**

class-validator のデコレータを付ける。DTO はクラスでなければ実行時検証ができない。

```ts
import { IsInt, IsString, MaxLength, Min, MinLength } from 'class-validator';

/** 注文作成の入力 */
export class CreateOrderDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  productName!: string;

  @IsInt()
  @Min(0)
  unitPrice!: number;

  @IsInt()
  @Min(1)
  quantity!: number;
}
```

`!` を付けているのは `strictPropertyInitialization: false` を設定していても `noUncheckedIndexedAccess` などとは無関係にプロパティ初期化の意図を明示するため。手順書 §2.2 は「`!` の大量付与を避けるため false にする」としているが、DTO は数個なので明示しておくほうが読み手に親切である。

- [ ] **Step 3: `create` の失敗するテストを追加**

`apps/api/src/orders/orders.service.spec.ts` の `MockPrisma` と `createMockPrisma` を差し替え、`describe('create', ...)` を追加する。

`MockPrisma` を次に置き換える:

```ts
interface MockPrisma {
  order: {
    findMany: jest.Mock;
    create: jest.Mock;
  };
}

function createMockPrisma(): MockPrisma {
  return { order: { findMany: jest.fn(), create: jest.fn() } };
}
```

ファイル末尾の `describe('findByUser', ...)` の後ろ、外側の `describe('OrdersService', ...)` の内側に追加する:

```ts
  describe('create', () => {
    it('作成した注文を割引適用後の合計付きで返す', async () => {
      prisma.order.create.mockResolvedValue({
        id: 'order-new',
        productName: 'マウス',
        unitPrice: 2000,
        quantity: 1,
        status: 'PENDING',
        user: { isMember: true },
      });

      const result = await service.create('user-1', {
        productName: 'マウス',
        unitPrice: 2000,
        quantity: 1,
      });

      // 2000 * 1 = 2000 → 会員なので 1800
      expect(result.discountedTotal).toBe(1800);
    });

    it('userId を紐付けて作成し、user を同時に取得する', async () => {
      prisma.order.create.mockResolvedValue({
        id: 'order-new',
        productName: 'マウス',
        unitPrice: 2000,
        quantity: 1,
        status: 'PENDING',
        user: { isMember: false },
      });

      await service.create('user-1', { productName: 'マウス', unitPrice: 2000, quantity: 1 });

      expect(prisma.order.create).toHaveBeenCalledWith({
        data: { userId: 'user-1', productName: 'マウス', unitPrice: 2000, quantity: 1 },
        include: { user: true },
      });
    });
  });
```

- [ ] **Step 4: テストが失敗することを確認**

```bash
pnpm --filter api test src/orders/orders.service.spec.ts
```

Expected: FAIL。`service.create is not a function` というエラーになる。

- [ ] **Step 5: `create` を実装**

`apps/api/src/orders/orders.service.ts` に import を 1 行追加し、`create` メソッドを追加する。

import 節に追加:

```ts
import type { CreateOrderDto } from './dto/create-order.dto';
```

`findByUser` の後ろに追加:

```ts
  /** 注文を作成し、会員割引を適用した合計付きで返す */
  async create(userId: string, dto: CreateOrderDto): Promise<OrderResponseDto> {
    const order = await this.prisma.order.create({
      data: {
        userId,
        productName: dto.productName,
        unitPrice: dto.unitPrice,
        quantity: dto.quantity,
      },
      include: { user: true },
    });

    return {
      id: order.id,
      productName: order.productName,
      unitPrice: order.unitPrice,
      quantity: order.quantity,
      status: order.status,
      discountedTotal: applyDiscount(order.unitPrice * order.quantity, order.user.isMember),
    };
  }
```

`findByUser` と `create` でレスポンス組み立てが重複しているが、**Phase 0 ではあえて重複させたままにする。** 手順書 §10 の「設計の一貫性が崩れ、重複が増える」は L5 で拾う想定の落とし穴であり、この重複が Phase 5 の AI レビューで指摘されるかどうか自体が検証材料になる。

- [ ] **Step 6: テストが通ることを確認**

```bash
pnpm --filter api test
```

Expected: PASS。合計 13 件（discount 6 + orders.service 7）成功。

- [ ] **Step 7: `apps/api/src/orders/orders.controller.ts` を作成**

デコレータの順序は `@Controller` を先、`@UseGuards` を後にする。**これは意図的な選択である。** 手順書 §3.2 の Semgrep カスタムルールは `@UseGuards(...)` が `@Controller(...)` の**上**にある形しか `pattern-not` で除外しない書き方になっている。NestJS で一般的な順序（`@Controller` が先）で書いておくことで、Phase 2 でそのルールが偽陽性を出すかどうか（設計書の仮説 5）を実地で検証できる。

**`CreateOrderDto` は `import type` にしてはいけない。** `emitDecoratorMetadata` が `@Body()` のためにクラス参照を実行時に出力する必要があり、`import type` だとその参照が消えて `ValidationPipe` が型を判別できなくなる。`OrderResponseDto` は戻り値の型注釈にしか使わないので `import type` で問題ない。

```ts
import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard, type AuthenticatedRequest } from '../auth/auth.guard';
import { CreateOrderDto } from './dto/create-order.dto';
import type { OrderResponseDto } from './dto/order-response.dto';
import { OrdersService } from './orders.service';

@Controller('orders')
@UseGuards(AuthGuard)
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  /** 認証済みユーザー自身の注文一覧 */
  @Get()
  findAll(@Req() request: AuthenticatedRequest): Promise<OrderResponseDto[]> {
    return this.ordersService.findByUser(request.userId);
  }

  /** 認証済みユーザー自身の注文を作成 */
  @Post()
  create(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateOrderDto,
  ): Promise<OrderResponseDto> {
    return this.ordersService.create(request.userId, dto);
  }
}
```

- [ ] **Step 8: `apps/api/src/orders/orders.module.ts` を作成**

```ts
import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({
  imports: [PrismaModule],
  controllers: [OrdersController],
  providers: [OrdersService],
})
export class OrdersModule {}
```

- [ ] **Step 9: `apps/api/src/app.module.ts` を作成**

```ts
import { Module } from '@nestjs/common';
import { OrdersModule } from './orders/orders.module';

@Module({
  imports: [OrdersModule],
})
export class AppModule {}
```

- [ ] **Step 10: `apps/api/src/main.ts` を作成**

`reflect-metadata` の import はデコレータのメタデータを使うために最初に必要。CORS を許可するのは Web（`localhost:5173`）から呼ぶため。

```ts
import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

const PORT = 3000;

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  app.enableCors({ origin: 'http://localhost:5173', allowedHeaders: ['content-type', 'x-user-id'] });
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );

  await app.listen(PORT);
}

void bootstrap();
```

- [ ] **Step 11: ビルドと typecheck を確認**

```bash
pnpm --filter api typecheck
pnpm --filter api build
```

Expected: どちらも exit 0。`apps/api/dist/main.js` が生成される。

- [ ] **Step 12: API を起動して `GET /orders` を確認**

別ターミナルで起動する。`turbo build` を先に走らせるのは、`start:dev` が `@repo/shared` のビルド出力を実行時に require するため。

```bash
pnpm turbo build
pnpm db:up
pnpm --filter api run start:dev
```

起動を確認したら別のシェルで:

```bash
# 会員ユーザーの ID を取得
MEMBER_ID=$(docker compose exec -T postgres psql -U postgres -d quality_gates -t -A \
  -c "SELECT id FROM \"User\" WHERE email = 'member@example.com';")

# 認証なし → 401
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/orders

# 認証あり → 200 と注文一覧
curl -s -H "x-user-id: $MEMBER_ID" http://localhost:3000/orders
```

Expected:
- 認証なしのリクエストが `401` を返す
- 認証ありのリクエストが 2 件の注文を返し、キーボード（1200×1）の `discountedTotal` が `1080`、ケーブル（300×2）の `discountedTotal` が `600` になっている

`discountedTotal` が期待値と違う場合は `applyDiscount` か `findByUser` の合計計算を見直す。

- [ ] **Step 13: `POST /orders` を確認**

```bash
curl -s -X POST http://localhost:3000/orders \
  -H "x-user-id: $MEMBER_ID" \
  -H 'content-type: application/json' \
  -d '{"productName":"マウス","unitPrice":2000,"quantity":1}'

# 入力検証が効くことを確認（quantity が 0 なので 400）
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:3000/orders \
  -H "x-user-id: $MEMBER_ID" \
  -H 'content-type: application/json' \
  -d '{"productName":"マウス","unitPrice":2000,"quantity":0}'
```

Expected:
- 1 つめが `discountedTotal: 1800` を含む JSON を返す
- 2 つめが `400` を返す

確認できたら API を停止する。

- [ ] **Step 14: コミット**

```bash
git add apps/api/src
git commit -m "feat: AuthGuard・OrdersController・アプリ起動処理を追加"
```

---

## Task 6: Web アプリ（TDD）

**Files:**
- Create: `apps/web/package.json`
- Create: `apps/web/tsconfig.json`
- Create: `apps/web/tsconfig.node.json`
- Create: `apps/web/vite.config.ts`
- Create: `apps/web/vitest.config.ts`
- Create: `apps/web/index.html`
- Create: `apps/web/src/env.d.ts`
- Create: `apps/web/src/test/setup.ts`
- Create: `apps/web/src/api/client.ts`
- Test: `apps/web/src/features/orders/orderTotal.test.ts`
- Create: `apps/web/src/features/orders/orderTotal.ts`
- Test: `apps/web/src/features/orders/OrderList.test.tsx`
- Create: `apps/web/src/features/orders/OrderList.tsx`
- Create: `apps/web/src/App.tsx`
- Create: `apps/web/src/main.tsx`

**Interfaces:**
- Consumes: `type OrderStatus`（Task 2 の `@repo/shared`、**型のみ import**）、API の `GET /orders`（Task 5）
- Produces:
  - `apps/web` のパッケージ名は `web`（手順書の `--filter web` に合わせる）
  - `src/api/client.ts` から `interface OrderView { id: string; productName: string; unitPrice: number; quantity: number; status: OrderStatus; discountedTotal: number }` と `fetchOrders(userId: string): Promise<OrderView[]>`
  - `src/features/orders/orderTotal.ts` から `sumDiscountedTotal(orders: readonly OrderView[]): number` と `isDiscountApplied(order: OrderView): boolean`
  - `src/features/orders/OrderList.tsx` から `OrderList(props: { userId: string }): React.JSX.Element`
  - Vite dev サーバは `http://localhost:5173`

- [ ] **Step 1: `apps/web/package.json` を作成**

```json
{
  "name": "web",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "typecheck": "tsc -p tsconfig.json --noEmit && tsc -p tsconfig.node.json --noEmit",
    "test": "vitest run"
  },
  "dependencies": {
    "react": "19.2.8",
    "react-dom": "19.2.8"
  },
  "devDependencies": {
    "@repo/shared": "workspace:*",
    "@repo/tsconfig": "workspace:*",
    "@testing-library/jest-dom": "7.0.0",
    "@testing-library/react": "16.3.2",
    "@types/react": "19.2.17",
    "@types/react-dom": "19.2.3",
    "@vitejs/plugin-react": "6.0.4",
    "@vitest/coverage-v8": "4.1.10",
    "jsdom": "30.0.0",
    "vite": "8.1.5",
    "vitest": "4.1.10"
  }
}
```

`@repo/shared` を `devDependencies` に置いているのは、**型のみ import するため実行時依存ではない**ことを表すため（Global Constraints 参照）。

- [ ] **Step 2: `apps/web/tsconfig.json` を作成**

手順書 §2.3 のとおり。`e2e` も対象に含めるのは Phase 3 で Playwright を足すため。

```json
{
  "extends": "@repo/tsconfig/base.json",
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "noEmit": true,
    "types": ["vite/client", "node"]
  },
  "include": ["src/**/*.ts", "src/**/*.tsx", "e2e/**/*.ts"]
}
```

**`references` は使わない。** プロジェクト参照を張ると `tsc -p tsconfig.json --noEmit` が参照先のビルド出力を要求し、`tsc -b` を使わない限り失敗する。代わりに Step 1 の `typecheck` スクリプトで 2 つの tsconfig をそれぞれ `--noEmit` で走らせる。

- [ ] **Step 3: `apps/web/tsconfig.node.json` を作成**

設定ファイル自身を型チェックの対象に含めるため。これを分けておかないと、Phase 1 で ESLint の `projectService: true` を有効にしたときに `vite.config.ts` が「どのプロジェクトにも属さない」と怒られる。`src` 側とは `types` が異なる（`vite/client` を含めない）ため別ファイルにする必要がある。

```json
{
  "extends": "@repo/tsconfig/base.json",
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "noEmit": true,
    "types": ["node"]
  },
  "include": ["vite.config.ts", "vitest.config.ts"]
}
```

- [ ] **Step 4: `apps/web/vite.config.ts` を作成**

`optimizeDeps.include` に `@repo/shared` を入れているのは、将来 Web が実行時に共有定数を使う場合に CommonJS のワークスペースパッケージを Vite が確実に前処理できるようにするため（Global Constraints 参照）。

```ts
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react()],
  server: { port: 5173 },
  optimizeDeps: { include: ['@repo/shared'] },
});
```

- [ ] **Step 5: `apps/web/vitest.config.ts` を作成**

手順書 §4.3 のとおり。

```ts
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    coverage: { provider: 'v8', reporter: ['text', 'lcov'] },
  },
});
```

- [ ] **Step 6: `apps/web/src/test/setup.ts` を作成**

```ts
import '@testing-library/jest-dom/vitest';
```

- [ ] **Step 7: `apps/web/src/env.d.ts` を作成**

`VITE_API_BASE_URL` を optional にしているのは、未設定時に既定値へフォールバックする実装が `@typescript-eslint/no-unnecessary-condition`（Phase 1 で有効化）に引っかからないようにするため。

```ts
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
```

- [ ] **Step 8: `apps/web/src/api/client.ts` を作成**

`OrderView` をここでローカル宣言するのは、Phase 3 で `openapi-typescript` の生成型（`schema.d.ts`）に差し替える境界をこのファイルに閉じ込めるため。

```ts
import type { OrderStatus } from '@repo/shared';

/** 注文一覧の表示に使う 1 件分のデータ */
export interface OrderView {
  id: string;
  productName: string;
  unitPrice: number;
  quantity: number;
  status: OrderStatus;
  discountedTotal: number;
}

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

- [ ] **Step 9: `orderTotal` の失敗するテストを書く**

`apps/web/src/features/orders/orderTotal.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import type { OrderView } from '../../api/client';
import { isDiscountApplied, sumDiscountedTotal } from './orderTotal';

function makeOrder(overrides: Partial<OrderView> = {}): OrderView {
  return {
    id: 'order-1',
    productName: 'キーボード',
    unitPrice: 1200,
    quantity: 1,
    status: 'PAID',
    discountedTotal: 1080,
    ...overrides,
  };
}

describe('sumDiscountedTotal', () => {
  it('空配列のときは 0 を返す', () => {
    expect(sumDiscountedTotal([])).toBe(0);
  });

  it('全注文の割引後合計を足し上げる', () => {
    const orders = [makeOrder({ discountedTotal: 1080 }), makeOrder({ discountedTotal: 600 })];
    expect(sumDiscountedTotal(orders)).toBe(1680);
  });
});

describe('isDiscountApplied', () => {
  it('割引後の合計が単価×数量より小さいときは true', () => {
    expect(isDiscountApplied(makeOrder({ unitPrice: 1200, quantity: 1, discountedTotal: 1080 }))).toBe(
      true,
    );
  });

  it('割引後の合計が単価×数量と等しいときは false', () => {
    expect(isDiscountApplied(makeOrder({ unitPrice: 300, quantity: 2, discountedTotal: 600 }))).toBe(
      false,
    );
  });
});
```

- [ ] **Step 10: テストが失敗することを確認**

```bash
pnpm install
pnpm --filter @repo/shared build
pnpm --filter web test
```

Expected: FAIL。`Failed to resolve import "./orderTotal"` というエラーになる。

- [ ] **Step 11: `orderTotal.ts` を実装**

`apps/web/src/features/orders/orderTotal.ts`:

```ts
import type { OrderView } from '../../api/client';

/** 全注文の割引後合計 */
export function sumDiscountedTotal(orders: readonly OrderView[]): number {
  return orders.reduce((sum, order) => sum + order.discountedTotal, 0);
}

/** この注文に割引が効いているか */
export function isDiscountApplied(order: OrderView): boolean {
  return order.discountedTotal < order.unitPrice * order.quantity;
}
```

- [ ] **Step 12: テストが通ることを確認**

```bash
pnpm --filter web test
```

Expected: PASS。4 件成功。

- [ ] **Step 13: `OrderList` の失敗するテストを書く**

`apps/web/src/features/orders/OrderList.test.tsx`:

読み込み中・エラー・空・データありの 4 状態を検証する。`fetchOrders` をモックするので API は不要。

```tsx
import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fetchOrders, type OrderView } from '../../api/client';
import { OrderList } from './OrderList';

// vi.mock はファイル先頭に巻き上げられるので、上の静的 import が
// そのままモックを受け取る。トップレベル await は不要。
vi.mock('../../api/client', () => ({ fetchOrders: vi.fn() }));

const fetchOrdersMock = vi.mocked(fetchOrders);

const SAMPLE_ORDERS: OrderView[] = [
  {
    id: 'order-1',
    productName: 'キーボード',
    unitPrice: 1200,
    quantity: 1,
    status: 'PAID',
    discountedTotal: 1080,
  },
  {
    id: 'order-2',
    productName: 'ケーブル',
    unitPrice: 300,
    quantity: 2,
    status: 'PENDING',
    discountedTotal: 600,
  },
];

describe('OrderList', () => {
  beforeEach(() => {
    fetchOrdersMock.mockReset();
  });

  it('読み込み中はその旨を表示する', () => {
    fetchOrdersMock.mockReturnValue(new Promise(() => undefined));

    render(<OrderList userId="user-1" />);

    expect(screen.getByText('読み込み中...')).toBeInTheDocument();
  });

  it('注文があるときは商品名と割引後合計を表示する', async () => {
    fetchOrdersMock.mockResolvedValue(SAMPLE_ORDERS);

    render(<OrderList userId="user-1" />);

    expect(await screen.findByText('キーボード')).toBeInTheDocument();
    expect(screen.getByText('ケーブル')).toBeInTheDocument();
    // 1080 + 600
    expect(screen.getByText('合計: 1680 円')).toBeInTheDocument();
  });

  it('割引が効いている注文には割引の印を付ける', async () => {
    fetchOrdersMock.mockResolvedValue(SAMPLE_ORDERS);

    render(<OrderList userId="user-1" />);

    // キーボードのみ割引が効いている
    expect(await screen.findByLabelText('キーボード は割引適用')).toBeInTheDocument();
    expect(screen.queryByLabelText('ケーブル は割引適用')).not.toBeInTheDocument();
  });

  it('注文が無いときはその旨を表示する', async () => {
    fetchOrdersMock.mockResolvedValue([]);

    render(<OrderList userId="user-1" />);

    expect(await screen.findByText('注文がありません')).toBeInTheDocument();
  });

  it('取得に失敗したときはエラーメッセージを表示する', async () => {
    fetchOrdersMock.mockRejectedValue(new Error('注文の取得に失敗しました（HTTP 401）'));

    render(<OrderList userId="user-1" />);

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '注文の取得に失敗しました（HTTP 401）',
    );
  });
});
```

- [ ] **Step 14: テストが失敗することを確認**

```bash
pnpm --filter web test
```

Expected: FAIL。`Failed to resolve import "./OrderList"` というエラーになる。

- [ ] **Step 15: `OrderList.tsx` を実装**

`apps/web/src/features/orders/OrderList.tsx`:

`cancelled` フラグでアンマウント後の setState を防いでいる。`useEffect` の依存配列に `userId` を入れているのは、Phase 1 で `react-hooks/exhaustive-deps: 'error'` を有効にしたときに通るようにするため。

React 19 の型定義はグローバル `JSX` 名前空間を提供しないので、`import type { JSX } from 'react'` で明示的に取り込む。

```tsx
import { useEffect, useState, type JSX } from 'react';
import { fetchOrders, type OrderView } from '../../api/client';
import { isDiscountApplied, sumDiscountedTotal } from './orderTotal';

interface OrderListProps {
  userId: string;
}

export function OrderList({ userId }: OrderListProps): JSX.Element {
  const [orders, setOrders] = useState<OrderView[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    fetchOrders(userId)
      .then((fetched) => {
        if (!cancelled) {
          setOrders(fetched);
        }
      })
      .catch((cause: unknown) => {
        if (!cancelled) {
          setError(cause instanceof Error ? cause.message : '不明なエラーが発生しました');
        }
      });

    return () => {
      cancelled = true;
    };
  }, [userId]);

  if (error !== null) {
    return <p role="alert">{error}</p>;
  }

  if (orders === null) {
    return <p>読み込み中...</p>;
  }

  if (orders.length === 0) {
    return <p>注文がありません</p>;
  }

  return (
    <section>
      <ul>
        {orders.map((order) => (
          <li key={order.id}>
            <span>{order.productName}</span>
            <span>
              {order.unitPrice} 円 × {order.quantity}
            </span>
            <span>{order.discountedTotal} 円</span>
            {isDiscountApplied(order) && (
              <span aria-label={`${order.productName} は割引適用`}>割引</span>
            )}
          </li>
        ))}
      </ul>
      <p>合計: {sumDiscountedTotal(orders)} 円</p>
    </section>
  );
}
```

- [ ] **Step 16: テストが通ることを確認**

```bash
pnpm --filter web test
```

Expected: PASS。9 件（orderTotal 4 + OrderList 5）成功。

- [ ] **Step 17: `App.tsx` / `main.tsx` / `index.html` を作成**

`apps/web/src/App.tsx`:

ユーザー ID を入力できるようにしているのは、会員と非会員で割引表示が変わることを手で確認できるようにするため。

```tsx
import { useState, type JSX } from 'react';
import { OrderList } from './features/orders/OrderList';

export function App(): JSX.Element {
  const [userId, setUserId] = useState('');

  return (
    <main>
      <h1>注文一覧</h1>
      <label>
        ユーザー ID
        <input
          value={userId}
          onChange={(event) => {
            setUserId(event.target.value);
          }}
        />
      </label>
      {userId === '' ? <p>ユーザー ID を入力してください</p> : <OrderList userId={userId} />}
    </main>
  );
}
```

`apps/web/src/main.tsx`:

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';

const container = document.getElementById('root');

if (container === null) {
  throw new Error('#root が見つかりません');
}

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
```

`apps/web/index.html`:

```html
<!doctype html>
<html lang="ja">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>注文一覧</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 18: typecheck とビルドを確認**

```bash
pnpm --filter web typecheck
pnpm --filter web build
```

Expected: どちらも exit 0。`apps/web/dist/index.html` が生成される。

- [ ] **Step 19: 画面が表示されることを確認**

3 つのシェルが必要。

```bash
# シェル1
pnpm db:up

# シェル2
pnpm --filter api run start:dev

# シェル3
pnpm --filter web run dev
```

会員ユーザーの ID を取得する:

```bash
docker compose exec -T postgres psql -U postgres -d quality_gates -t -A \
  -c "SELECT id FROM \"User\" WHERE email = 'member@example.com';"
```

`http://localhost:5173` を開き、取得した ID を入力する。

Expected:
- 注文 2 件（キーボード、ケーブル）が表示される
- キーボードの行に「割引」の表示があり、ケーブルの行には無い
- 「合計: 1680 円」が表示される

非会員（`guest@example.com`）の ID でも試す。

Expected: モニター 1 件（5000 円）が表示され、「割引」の表示は無く、「合計: 5000 円」になる。

確認できたら 3 つのプロセスを停止する。

- [ ] **Step 20: コミット**

```bash
git add apps/web .gitignore pnpm-lock.yaml
git commit -m "feat: React/Vite の注文一覧画面を追加"
```

---

## Task 7: turbo タスク配線と Phase 0 完了確認

**Files:**
- Modify: `packages/shared/package.json`（`test` スクリプトを追加）
- Create: `README.md` の開発手順セクション（既存 `README.md` を Modify）

**Interfaces:**
- Consumes: Task 1〜6 のすべて
- Produces:
  - `pnpm turbo build` / `pnpm turbo typecheck` / `pnpm turbo test` がリポジトリ全体で通る状態
  - `README.md` に起動手順が記載された状態

- [ ] **Step 1: `packages/shared` に `test` スクリプトを追加**

`turbo test` は全パッケージの `test` を探す。`packages/shared` は定数と型だけでテスト対象が無いため、`turbo` が失敗しないように何もしない `test` を置く。

`packages/shared/package.json` の `scripts` を次に置き換える:

```json
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "typecheck": "tsc -p tsconfig.json --noEmit",
    "test": "echo 'テスト対象なし（定数と型のみ）'"
  },
```

- [ ] **Step 2: `packages/tsconfig` に turbo タスクが無いことを確認**

`packages/tsconfig/package.json` には `scripts` が無い。turbo はスクリプトが無いパッケージを黙ってスキップするので追加は不要。

```bash
pnpm turbo build --dry-run=text
```

Expected: 出力の `Tasks to Run` に `@repo/shared#build` / `api#build` / `web#build` の 3 つだけが並び、`@repo/tsconfig` は現れない。

- [ ] **Step 3: turbo でビルドが通ることを確認**

```bash
pnpm turbo build
```

Expected: 3 パッケージすべて成功。`@repo/shared` が `api` / `web` より先に実行される（`dependsOn: ["^build"]` による）。

- [ ] **Step 4: turbo で typecheck が通ることを確認**

```bash
pnpm turbo typecheck
```

Expected: 3 パッケージすべて成功、エラーなし。

- [ ] **Step 5: turbo でテストが通ることを確認**

```bash
pnpm turbo test
```

Expected: `api` 13 件・`web` 9 件が成功、`@repo/shared` はメッセージのみ。

- [ ] **Step 6: キャッシュが効くことを確認**

```bash
pnpm turbo build
```

Expected: `FULL TURBO` と表示され、全タスクがキャッシュから復元される。これは Phase 1 以降で CI 時間を測るときの前提になる。

- [ ] **Step 7: `README.md` に開発手順を書く**

既存の `README.md` を次の内容に置き換える（以下は 4 連バッククォートで囲んでいるが、`README.md` に書くのは中身だけ）。

`pnpm turbo build` をセットアップ手順に含めているのは、`apps/api` の `start:dev` が `@repo/shared` のビルド出力（`dist/index.js`）を実行時に require するため。ビルド前に起動すると `Cannot find module '@repo/shared'` になる。

````markdown
# sandbox-quality-gates-test

多層品質ゲート L1〜L5 の検証用サンドボックス。

- 導入手順書: `docs/多層品質ゲート_L1-L5_導入手順_NestJS-React.md`
- 検証環境の設計: `docs/superpowers/specs/2026-07-29-multilayer-quality-gates-verification-design.md`

## 必要なもの

- Node.js 24 系
- pnpm 11 系
- Docker（PostgreSQL・Semgrep・OSV-Scanner・gitleaks の実行に使う）

## セットアップ

```bash
pnpm install
cp .env.example .env
cp .env.example apps/api/.env
pnpm turbo build
pnpm db:up
pnpm --filter api exec prisma migrate deploy
pnpm --filter api run db:seed
```

## 起動

```bash
# API（http://localhost:3000）
pnpm --filter api run start:dev

# Web（http://localhost:5173）
pnpm --filter web run dev
```

Web を開いたら、以下のコマンドで取得したユーザー ID を入力する。

```bash
docker compose exec -T postgres psql -U postgres -d quality_gates -t -A \
  -c "SELECT email, id FROM \"User\";"
```

## 検証

```bash
pnpm turbo build typecheck test
```
````

- [ ] **Step 8: 手順書どおりのセットアップが白紙から通ることを確認**

`README.md` の手順が実際に通るかを、生成物を消した状態から確認する。

```bash
rm -rf node_modules apps/*/node_modules packages/*/node_modules
rm -rf apps/*/dist packages/*/dist .turbo apps/*/.turbo packages/*/.turbo
pnpm install
pnpm turbo build typecheck test
```

Expected: すべて成功。失敗した場合は `README.md` の手順に不足があるので追記する。

- [ ] **Step 9: コミット**

```bash
git add README.md packages/shared/package.json
git commit -m "docs: 開発手順を README に追加し turbo タスクを配線"
```

---

## Phase 0 完了条件

設計書 §10 の Phase 0 完了条件に対応する。

- [ ] `pnpm turbo build` が 3 パッケージすべてで成功する
- [ ] `pnpm turbo typecheck` がエラーなしで通る
- [ ] `pnpm turbo test` が 22 件（api 13 + web 9）成功する
- [ ] `GET /orders` が認証なしで `401`、認証ありで注文一覧を返す
- [ ] `POST /orders` が注文を作成し、不正な入力に `400` を返す
- [ ] `http://localhost:5173` で注文一覧が表示され、会員のみ「割引」表示が出る
- [ ] `README.md` の手順が白紙の状態から通る

## Phase 1 への申し送り

Phase 0 の実装中に判明し、Phase 1（L1 + 検証ハーネス）で扱う必要がある事項。

| # | 内容 | Phase 1 での対応 |
|---|---|---|
| 1 | `prisma/seed.ts` が `console.info` / `console.error` を使っている | 手順書 §2.4 の `no-console: 'error'` に引っかかる。`eslint.config.js` で `prisma/**` を対象外にするか、`require-description` 付きの `eslint-disable-next-line` を書くかを判断する |
| 2 | ルートと `apps/api` の `eslint.config.js` が手順書に無い（設計書の仮説 6） | フラットコンフィグをルート・`apps/api`・`apps/web` の 3 箇所に置く必要があるかを確認し、結論を記録する |
| 3 | `apps/web/tsconfig.node.json` を分けてある | ESLint の `projectService: true` が `vite.config.ts` / `vitest.config.ts` を解決できるかを確認する |
| 4 | `apps/api/tsconfig.spec.json` で `noUnusedLocals` を緩めている | ESLint 側の型情報付きルールがどの tsconfig を使うかで挙動が変わる可能性を確認する |
| 5 | `OrdersController` のデコレータ順が `@Controller` → `@UseGuards` | Phase 2 の仮説 5（Semgrep カスタムルールの偽陽性）の検証対象。Phase 1 では変更しない |
| 6 | `OrdersService.findByUser` と `create` でレスポンス組み立てが重複している | 意図的な重複。Phase 5 の `L5-01-duplicate-logic` および AI レビューの検証材料なので解消しない |
| 7 | TypeScript は 5.9.3 に固定（最新 7.0.2 は `ts-jest` / `typescript-eslint` が非対応） | Phase 6 の検証レポートに「手順書は TypeScript バージョン制約に触れていない」として記録する |
| 8 | Prisma は 6.19.3 に固定（7 系は生成物が TS ソースでゲート対象になる） | Phase 6 の検証レポートに追加検証候補として記録する |
