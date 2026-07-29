# 多層品質ゲート L1〜L5 導入手順書

**対象スタック**：NestJS（API）＋ React/Vite（Web）／全 TypeScript
**リポジトリ構成**：モノレポ
**CI 基盤**：Google Cloud Build
**テストランナー**：API = Jest、Web = Vitest

> 本書は調査レポート「人間のコードレビューを廃止・最小化しても品質を保証する開発方法」10.1節の多層ゲートのうち、マージ前に回す **L1〜L5** を実装するための準備と手順をまとめたものです。L6（マージゲート）以降は末尾に接続方法のみ記載します。

---

## 0. 全体像

### 5つの層と、それぞれが止めるもの

| 層 | 内容 | 止める対象 | PRブロック |
|---|---|---|---|
| **L1** | 型チェック＋Lint | 型不整合・スタイル・明白な誤り | ● 必須 |
| **L2** | SAST＋依存関係スキャン | 既知脆弱性・供給網リスク | ● 必須 |
| **L3** | テスト（unit〜e2e） | 機能欠陥・回帰 | ● 必須 |
| **L4** | ミューテーションテスト | 空虚なテスト・カバレッジ偽装 | ● 差分のみ必須 |
| **L5** | AIレビュー | 観点漏れ・可読性 | ○ 非ブロック |

### 設計原則

1. **PRゲートに置くのは「速く」「決定的」なものだけ。** flaky なもの・遅いものを必須にすると、失敗が常態化して誰も見なくなります。
2. **重いものは差分に絞る。** L4 は変更ファイルのみ、フル実行は nightly。
3. **L5 は単独の防御線にしない。** AIレビューはブロックさせず、L1〜L4 の上に重ねる補助線として扱います。
4. **既存コードは一気に厳格化しない。** 新規・変更コードにのみ厳格ルールを適用します（Clean as You Code）。

---

## 1. 事前準備

### 1.1 リポジトリ構成

```
.
├── apps/
│   ├── api/                    # NestJS
│   │   ├── src/
│   │   ├── test/
│   │   ├── jest.config.ts
│   │   ├── stryker.config.json
│   │   └── tsconfig.json
│   └── web/                    # React + Vite
│       ├── src/
│       ├── e2e/                # Playwright
│       ├── vitest.config.ts
│       ├── stryker.config.json
│       └── tsconfig.json
├── packages/
│   ├── shared/                 # 共有型・ユーティリティ
│   ├── eslint-config/          # ESLint 共通設定
│   └── tsconfig/               # tsconfig 共通設定
├── .claude/
│   ├── skills/code-review/     # L5 レビュー観点
│   └── agents/reviewer.md
├── .semgrep/                   # カスタムルール
├── cloudbuild.pr.yaml          # PR 用（L1〜L5）
├── cloudbuild.nightly.yaml     # 夜間用（フル実行）
├── pnpm-workspace.yaml
├── turbo.json
└── package.json
```

### 1.2 モノレポ基盤の導入

pnpm workspaces ＋ Turborepo を推奨します。Turborepo の `--filter` で変更のあったパッケージだけを対象にでき、CI 時間を大きく削減できます。

```bash
corepack enable
pnpm init
pnpm add -Dw turbo
```

```yaml
# pnpm-workspace.yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

```jsonc
// turbo.json
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

### 1.3 Cloud Build 側の準備

| 項目 | 内容 |
|---|---|
| トリガー | PR 用（`cloudbuild.pr.yaml`）と nightly 用（`cloudbuild.nightly.yaml`）の2本を作成 |
| SCM 連携 | GitHub の場合は Cloud Build GitHub アプリを導入。ビルド結果が GitHub のチェックとして送信され、L6 の必須ステータスチェックに指定できる |
| Secret Manager | Semgrep トークン、Anthropic API キー等を登録し、`availableSecrets` から参照 |
| マシンタイプ | `E2_HIGHCPU_8` 程度。Stryker と Jest の並列実行で効きます |
| 差分取得 | Cloud Build は浅いクローンのため、ベースブランチを明示的に fetch する必要があります |

```bash
# 差分ファイルの取得（各ステップで使い回す）
git fetch --no-tags --depth=50 origin "$_BASE_BRANCH"
git diff --name-only "origin/$_BASE_BRANCH...HEAD" -- '*.ts' '*.tsx'
```

---

## 2. L1：型チェック＋Lint

### 2.1 共通 tsconfig

```jsonc
// packages/tsconfig/base.json
{
  "compilerOptions": {
    "strict": true,
    // strict に含まれないが有効なもの
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    // 運用上の必須
    "isolatedModules": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

> **`exactOptionalPropertyTypes` について**：効果は高いものの、既存ライブラリの型と衝突して大量のエラーが出ることがあります。導入は第2フェーズに回すことを推奨します。

### 2.2 NestJS 側の注意点

NestJS はデコレータと DI を多用するため、そのままでは `strict` と相性の悪い箇所があります。

```jsonc
// apps/api/tsconfig.json
{
  "extends": "@repo/tsconfig/base.json",
  "compilerOptions": {
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    // DI・Entity のプロパティに ! を大量付与するのを避けるため false
    "strictPropertyInitialization": false,
    "target": "ES2022",
    "module": "commonjs",
    "outDir": "./dist"
  }
}
```

### 2.3 Web 側

```jsonc
// apps/web/tsconfig.json
{
  "extends": "@repo/tsconfig/base.json",
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "noEmit": true
  }
}
```

### 2.4 ESLint 共通設定

```bash
pnpm add -Dw eslint typescript-eslint @eslint/js \
  @eslint-community/eslint-plugin-eslint-comments \
  eslint-plugin-react-hooks eslint-plugin-jsx-a11y
```

```js
// packages/eslint-config/index.js
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import comments from '@eslint-community/eslint-plugin-eslint-comments/configs';

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  comments.recommended,
  {
    linterOptions: {
      // 効いていない抑制コメント（＝負債）を検出
      reportUnusedDisableDirectives: 'error',
    },
    languageOptions: {
      parserOptions: { projectService: true },
    },
    rules: {
      // --- 厳選した追加ルール ---
      '@typescript-eslint/no-floating-promises': 'error',   // NestJS で特に重要
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unnecessary-condition': 'error',
      'eqeqeq': ['error', 'always'],
      'no-console': 'error',

      // --- 抑制コメントを締める（AI前提では最重要）---
      '@eslint-community/eslint-comments/no-unlimited-disable': 'error',
      '@eslint-community/eslint-comments/require-description': 'error',
      '@eslint-community/eslint-comments/no-unused-disable': 'error',
    },
  },
);
```

Web 側は React 固有ルールを追加します。

```js
// apps/web/eslint.config.js
import base from '@repo/eslint-config';
import reactHooks from 'eslint-plugin-react-hooks';
import jsxA11y from 'eslint-plugin-jsx-a11y';

export default [
  ...base,
  reactHooks.configs['recommended-latest'],
  jsxA11y.flatConfigs.recommended,
  {
    rules: {
      'react-hooks/exhaustive-deps': 'error',  // warn ではなく error に
      // Web から API の内部実装を直接 import させない
      'no-restricted-imports': ['error', {
        patterns: [{ group: ['**/apps/api/src/**'], message: '共有は packages/shared 経由で' }],
      }],
    },
  },
];
```

### 2.5 実行コマンド

```bash
pnpm turbo typecheck    # tsc --noEmit を各アプリで
pnpm eslint . --max-warnings=0
```

> **`--max-warnings=0` が要点です。** warn は CI では実質無視され溜まる一方になるため、ゲートにするなら警告ゼロを強制します。

### 2.6 既存コードの扱い

既存コードごと厳格化すると大量の警告に埋もれて全部無視されます。次のいずれかで凍結してください。

- 既存ファイルを `eslint.config.js` の別ブロックでルール緩和し、新規ファイルのみ厳格化
- 差分に対してのみ lint を実行（`eslint $(git diff --name-only origin/main...HEAD -- '*.ts' '*.tsx')`）

---

## 3. L2：SAST ＋ 依存関係スキャン

### 3.1 ツール選定（Cloud Build 前提）

CodeQL は SARIF のアップロード先が GitHub 前提となるため、Cloud Build 環境では **Semgrep** を主軸に据えるのが素直です。依存関係スキャンには Google 製の **OSV-Scanner** を使います。

| 対象 | ツール | 備考 |
|---|---|---|
| 自コードの脆弱性 | Semgrep | CLI がコンテナで完結。ルールセットを選択可能 |
| 依存ライブラリ | OSV-Scanner | lockfile を直接読む。Google 製で GCP と相性良好 |
| シークレット混入 | gitleaks | コミット履歴も走査可能 |

### 3.2 Semgrep

```yaml
# .semgrep.yml（ルールセットの指定）
rules: []   # カスタムルールはここに追加
```

```bash
semgrep ci \
  --config p/typescript \
  --config p/nodejs \
  --config p/react \
  --config p/owasp-top-ten \
  --config p/secrets \
  --config .semgrep/ \
  --error
```

NestJS 固有の観点はカスタムルール化しておくと効果的です。

```yaml
# .semgrep/nestjs.yml
rules:
  - id: nest-controller-without-guard
    message: |
      Controller に認可ガードが設定されていません。
      @UseGuards() を付与するか、意図的に公開する場合は @Public() を明示してください。
    languages: [typescript]
    severity: ERROR
    patterns:
      - pattern: |
          @Controller(...)
          class $C { ... }
      - pattern-not: |
          @UseGuards(...)
          @Controller(...)
          class $C { ... }
```

> 認可・アクセス制御は SAST が最も苦手とする領域です（OWASP）。汎用ルールに任せきらず、自社の規約をカスタムルール化してください。

### 3.3 依存関係（架空パッケージ・供給網対策）

AI 生成コードでは「存在しないパッケージ」を import するハルシネーションが発生します（商用モデルで 5.2%、OSS モデルで 21.7% という調査結果）。攻撃者がその名前を先に登録する slopsquatting のリスクがあるため、次の3点を必ず入れてください。

```bash
# ① lockfile を絶対とする＋インストールスクリプトを無効化
pnpm install --frozen-lockfile --ignore-scripts

# ② 既知脆弱性スキャン
osv-scanner --lockfile=pnpm-lock.yaml

# ③ シークレット混入チェック
gitleaks detect --no-git --redact
```

さらに、**新規依存の追加は人間承認を必須**にするのが有効です。

```bash
# 新しい依存が追加されたかを検出し、検出時はラベルを付けて人間レビューへ回す
git diff "origin/$_BASE_BRANCH...HEAD" -- '**/package.json' \
  | grep -E '^\+\s+"' && echo "NEW_DEPENDENCY_DETECTED"
```

---

## 4. L3：テスト

### 4.1 テスト種別の配置

| 種別 | 場所 | ツール | 毎PR |
|---|---|---|---|
| ユニット（API） | `apps/api/src/**/*.spec.ts` | Jest | ● |
| 統合（API＋DB） | `apps/api/test/**/*.int-spec.ts` | Jest + Testcontainers | ● |
| E2E（API） | `apps/api/test/**/*.e2e-spec.ts` | Jest + supertest | ● |
| ユニット（Web） | `apps/web/src/**/*.test.tsx` | Vitest + Testing Library | ● |
| E2E（Web） | `apps/web/e2e/**/*.spec.ts` | Playwright | △ 主要導線のみ |
| プロパティベース | 各所に混在 | fast-check | ● 回数を絞って |

### 4.2 API：Jest ＋ Testcontainers

DB をモックせず実物の PostgreSQL を立てることで、統合テストの信頼性が上がります。

```bash
pnpm add -D --filter api @testcontainers/postgresql supertest @types/supertest
```

```ts
// apps/api/test/setup-db.ts
import { PostgreSqlContainer, StartedPostgreSqlContainer } from '@testcontainers/postgresql';

let container: StartedPostgreSqlContainer;

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16-alpine').start();
  process.env.DATABASE_URL = container.getConnectionUri();
}, 60_000);

afterAll(async () => {
  await container?.stop();
});
```

> Cloud Build で Testcontainers を使う場合は Docker ソケットが必要です。`cloudbuild.yaml` の該当ステップで `docker` イメージを使うか、Cloud Build の Docker デーモンを利用してください。難しい場合は、統合テストのみ nightly に回す判断も現実的です。

### 4.3 Web：Vitest ＋ Testing Library

```ts
// apps/web/vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    coverage: { provider: 'v8', reporter: ['text', 'lcov'] },
  },
});
```

### 4.4 契約テスト：モノレポでは OpenAPI 型生成を推奨

API と Web が同一リポジトリにあるなら、Pact のような消費者駆動契約より、**NestJS の OpenAPI から型を生成して Web が消費する**ほうが軽量で確実です。型レベルで契約違反がコンパイルエラーになります。

```bash
pnpm add -D --filter api @nestjs/swagger
pnpm add -D --filter web openapi-typescript
```

```bash
# ① API から OpenAPI スキーマを出力
pnpm --filter api run generate:openapi   # → openapi.json

# ② Web 用の型を生成
pnpm --filter web exec openapi-typescript ../../openapi.json -o src/api/schema.d.ts

# ③ 生成物に差分が出たらCIを落とす（＝スキーマ更新漏れの検出）
git diff --exit-code apps/web/src/api/schema.d.ts
```

> 将来 API と Web を別リポジトリ・別チームに分ける場合は、この時点で Pact への移行を検討してください。

### 4.5 プロパティベーステスト：fast-check

Jest / Vitest のどちらでも同じ書き方で使えます。

```bash
pnpm add -Dw fast-check
```

```ts
import fc from 'fast-check';
import { applyDiscount } from './discount';

const NUM_RUNS = Number(process.env.FC_NUM_RUNS ?? 100);

test('割引後の価格は元の価格を超えない', () => {
  fc.assert(
    fc.property(
      fc.integer({ min: 0, max: 1_000_000 }),
      fc.boolean(),
      (price, isMember) => applyDiscount(price, isMember) <= price,
    ),
    { numRuns: NUM_RUNS },
  );
});
```

**探索と回帰を分ける**のがポイントです。

| | 毎PR | nightly |
|---|---|---|
| `FC_NUM_RUNS` | 100（数秒で終わる） | 10000（時間をかけて探索） |
| 役割 | 回帰の確認 | 新規バグの探索 |

失敗した反例は必ずテストコードに固定化してください。

```ts
{ numRuns: NUM_RUNS, examples: [[1000, true]] }  // 過去に落ちたケースを常に実行
```

### 4.6 実行コマンド

```bash
pnpm turbo test --filter='...[origin/main]'   # 変更に関係するパッケージのみ
```

---

## 5. L4：ミューテーションテスト

### 5.1 導入

API は Jest ランナー、Web は Vitest ランナー（Stryker v7.0 以降で対応）を使います。

```bash
pnpm add -D --filter api @stryker-mutator/core @stryker-mutator/jest-runner
pnpm add -D --filter web @stryker-mutator/core @stryker-mutator/vitest-runner
```

### 5.2 設定

```jsonc
// apps/api/stryker.config.json
{
  "$schema": "./node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "testRunner": "jest",
  "jest": { "configFile": "jest.config.ts" },
  "coverageAnalysis": "perTest",
  "mutate": ["src/**/*.ts", "!src/**/*.spec.ts", "!src/main.ts", "!src/**/*.module.ts"],
  "incremental": true,
  "incrementalFile": "reports/stryker-incremental.json",
  "thresholds": { "high": 80, "low": 60, "break": 60 },
  "reporters": ["clear-text", "html", "json"]
}
```

```jsonc
// apps/web/stryker.config.json
{
  "testRunner": "vitest",
  "vitest": { "configFile": "vitest.config.ts", "related": true },
  "mutate": ["src/**/*.{ts,tsx}", "!src/**/*.test.{ts,tsx}", "!src/main.tsx"],
  "incremental": true,
  "thresholds": { "high": 80, "low": 60, "break": 60 }
}
```

**除外すべき対象**：`*.module.ts`（DI 定義のみでロジックがない）、エントリポイント、生成コード。これらを含めるとスコアが不当に下がります。

### 5.3 PR では差分のみ

```bash
#!/usr/bin/env bash
# scripts/stryker-diff.sh
set -euo pipefail

git fetch --no-tags --depth=50 origin "${BASE_BRANCH:-main}"
CHANGED=$(git diff --name-only "origin/${BASE_BRANCH:-main}...HEAD" \
  -- 'apps/api/src/**/*.ts' | grep -v '\.spec\.ts$' || true)

if [ -z "$CHANGED" ]; then
  echo "変更なし。スキップします。"
  exit 0
fi

pnpm --filter api exec stryker run --mutate "$(echo "$CHANGED" | paste -sd, -)"
```

### 5.4 incremental の注意点

Stryker の `incremental` および PIT の incremental analysis は、前回結果を再利用して高速化する仕組みです。PIT の公式ドキュメントは、この最適化が **「誤差を持ち込みうる（introduce a degree of potential error）」「その仮定は未検証（unproven）」** と明記しています。Stryker も同様の性質を持つと考えるべきです。

**対策**：PR では差分＋incremental で高速に回し、**nightly で `--force` を付けてフル実行**し、蓄積した誤差をリセットしてください。

```bash
# nightly
pnpm --filter api exec stryker run --force
pnpm --filter web exec stryker run --force
```

### 5.5 閾値の決め方

いきなり 60% を課すと落ち続けます。次の順で上げてください。

1. まず `break: null` で計測のみ実施し、現状値を把握する
2. 現状値の少し下（例：現状 45% なら 40%）を `break` に設定
3. 四半期ごとに 5〜10 ポイントずつ引き上げる

---

## 6. L5：AIレビュー

### 6.1 位置づけ

**ブロックさせません。** マージ可否の最終判定を LLM に委ねてはいけません。理由は次の3点です。

- LLM の脆弱性判定は非頑健（変数名を変えただけで結論が変わる例が報告されている）
- 存在しないバグを捏造することがある
- 高性能モデルほど誤りが似通うため、生成と同系統モデルの単独判定は防御線にならない

### 6.2 レビュー観点の体系化

```markdown
<!-- .claude/skills/code-review/SKILL.md -->
---
name: code-review
description: PR の差分を、正しさ・要件の観点でレビューする
---

## 手順
1. `git diff origin/main...HEAD` で差分を取得
2. 下記チェックリストの各項目について「該当／非該当＋理由」を必ず出力
3. 指摘は「正しさ・要件に関わるもの」のみ。スタイル・好みの指摘はしない
   （lint で機械的に検出できるものは報告不要）

## チェックリスト
- [ ] 境界値：閾値のちょうど上・ちょうど・すぐ下のテストがあるか
- [ ] 異常系：null / 空 / 型不正 / 上限超過
- [ ] 権限：他ユーザーのリソースにアクセスできないか（Controller に Guard があるか）
- [ ] 冪等性：同じリクエストを2回送ったとき
- [ ] 並行性：同時更新・競合
- [ ] 障害時：外部サービスがタイムアウト・エラーを返したとき
- [ ] トランザクション境界：複数テーブル更新が原子的か
- [ ] N+1：ORM のクエリが件数に比例して増えないか

## 出力形式
| 重大度 | ファイル:行 | 指摘 | 根拠 |
```

> 最後の「スタイル・好みの指摘はしない」が重要です。gap を探せと指示されたレビュアは、健全な成果物でも何かしら報告しがちで、それを全部追うと過剰設計を招きます。

### 6.3 Cloud Build からの実行

```yaml
- id: ai-review
  name: node:22
  entrypoint: bash
  secretEnv: ['ANTHROPIC_API_KEY']
  args:
    - -c
    - |
      npm i -g @anthropic-ai/claude-code
      git fetch --no-tags --depth=50 origin "$_BASE_BRANCH"
      claude -p "/code-review origin/$_BASE_BRANCH...HEAD" \
        --output-format text > review.md || true   # 失敗してもビルドは落とさない
      cat review.md
  waitFor: ['install']
```

### 6.4 運用：人間の指摘をルール化して育てる

最初から完璧なチェックリストは書けません。次の順で育ててください。

1. 最初の1〜2か月は人間レビューを残し、**指摘を記録・分類**する
2. **3回以上繰り返された指摘だけ**をルール化する
3. 機械判定できるもの → ESLint カスタムルール / Semgrep へ降ろす
4. 判断が要るもの → 上記チェックリストへ追加
5. 本番障害が出たら「なぜテストで捕まらなかったか」を観点に還元
6. 四半期ごとに棚卸しし、**発火していない・偽陽性ばかりのルールは削除**

---

## 7. cloudbuild.pr.yaml（統合）

```yaml
timeout: '1800s'
options:
  machineType: 'E2_HIGHCPU_8'
  env:
    - 'CI=true'
    - 'FC_NUM_RUNS=100'

availableSecrets:
  secretManager:
    - versionName: projects/$PROJECT_ID/secrets/anthropic-api-key/versions/latest
      env: 'ANTHROPIC_API_KEY'

steps:
  # ---------- 準備 ----------
  - id: install
    name: node:22
    entrypoint: bash
    args:
      - -c
      - |
        corepack enable
        pnpm install --frozen-lockfile --ignore-scripts
        git fetch --no-tags --depth=50 origin "$_BASE_BRANCH"

  # ---------- L1 静的解析（並列）----------
  - id: l1-typecheck
    name: node:22
    entrypoint: bash
    args: ['-c', 'corepack enable && pnpm turbo typecheck']
    waitFor: ['install']

  - id: l1-lint
    name: node:22
    entrypoint: bash
    args: ['-c', 'corepack enable && pnpm eslint . --max-warnings=0']
    waitFor: ['install']

  # ---------- L2 SAST・依存（並列）----------
  - id: l2-semgrep
    name: semgrep/semgrep
    entrypoint: semgrep
    args:
      - ci
      - --config=p/typescript
      - --config=p/nodejs
      - --config=p/react
      - --config=p/owasp-top-ten
      - --config=p/secrets
      - --config=.semgrep/
      - --error
    waitFor: ['install']

  - id: l2-osv
    name: ghcr.io/google/osv-scanner
    args: ['--lockfile=pnpm-lock.yaml']
    waitFor: ['install']

  - id: l2-new-deps
    name: gcr.io/cloud-builders/git
    entrypoint: bash
    args:
      - -c
      - |
        if git diff "origin/$_BASE_BRANCH...HEAD" -- '**/package.json' | grep -qE '^\+\s+"'; then
          echo "⚠️  新規依存が追加されています。人間レビューが必要です。"
        fi
    waitFor: ['install']

  # ---------- L3 テスト ----------
  - id: l3-test
    name: node:22
    entrypoint: bash
    args: ['-c', 'corepack enable && pnpm turbo test --filter="...[origin/$_BASE_BRANCH]"']
    waitFor: ['l1-typecheck']

  - id: l3-openapi-drift
    name: node:22
    entrypoint: bash
    args:
      - -c
      - |
        corepack enable
        pnpm --filter api run generate:openapi
        pnpm --filter web exec openapi-typescript ../../openapi.json -o src/api/schema.d.ts
        git diff --exit-code apps/web/src/api/schema.d.ts \
          || { echo "❌ OpenAPI スキーマと生成型に差分があります。生成物をコミットしてください。"; exit 1; }
    waitFor: ['l1-typecheck']

  # ---------- L4 ミューテーション（差分のみ）----------
  - id: l4-mutation
    name: node:22
    entrypoint: bash
    env: ['BASE_BRANCH=$_BASE_BRANCH']
    args: ['-c', 'corepack enable && ./scripts/stryker-diff.sh']
    waitFor: ['l3-test']

  # ---------- L5 AIレビュー（非ブロック）----------
  - id: l5-ai-review
    name: node:22
    entrypoint: bash
    secretEnv: ['ANTHROPIC_API_KEY']
    args:
      - -c
      - |
        npm i -g @anthropic-ai/claude-code
        claude -p "/code-review origin/$_BASE_BRANCH...HEAD" > review.md || true
        cat review.md
    waitFor: ['install']

substitutions:
  _BASE_BRANCH: 'main'
```

### nightly（フル実行）

```yaml
# cloudbuild.nightly.yaml（要点のみ）
steps:
  - id: mutation-full
    name: node:22
    entrypoint: bash
    args:
      - -c
      - |
        corepack enable
        pnpm --filter api exec stryker run --force
        pnpm --filter web exec stryker run --force

  - id: pbt-deep
    name: node:22
    entrypoint: bash
    env: ['FC_NUM_RUNS=10000']
    args: ['-c', 'corepack enable && pnpm turbo test']

  - id: e2e-full
    name: mcr.microsoft.com/playwright:v1.50.0-jammy
    entrypoint: bash
    args: ['-c', 'corepack enable && pnpm --filter web exec playwright test']
```

---

## 8. L6 への接続（参考）

L1〜L5 を Cloud Build で回したあと、マージゲートに繋ぎます。

- Cloud Build GitHub アプリ経由でトリガーすると、結果が GitHub のチェックとして送信されます。これをブランチ保護の**必須ステータスチェック**に指定してください（L5 の AI レビューは**含めない**）。
- `CODEOWNERS` で、人間レビューを残すべき領域だけ承認必須にします。

```
# .github/CODEOWNERS
# 意図・設計・認可・コンプラに関わる箇所のみ人間必須
/apps/api/src/auth/          @security-team
/apps/api/src/**/*.guard.ts  @security-team
/packages/shared/            @tech-lead
/**/package.json             @tech-lead        # 新規依存の混入対策
/cloudbuild*.yaml            @tech-lead
```

---

## 9. 導入ロードマップ

一度に全部入れると確実に破綻します。次の順序を推奨します。

| フェーズ | 期間目安 | 内容 | 完了条件 |
|---|---|---|---|
| **1** | 1〜2週 | L1 導入。既存コードはベースラインで凍結 | 新規コードで typecheck / lint がゼロ警告 |
| **2** | 1〜2週 | L2 導入。Semgrep・OSV-Scanner を必須化 | 既存の指摘をトリアージし終える |
| **3** | 2〜4週 | L3 整備。テストピラミッドの土台を作る | 主要ユースケースの統合テストが揃う |
| **4** | 2〜4週 | L4 を計測のみで導入（`break: null`） | 現状のミューテーションスコアを把握 |
| **5** | 1〜2週 | L4 の閾値を有効化。L5 を非ブロックで導入 | ゲートが安定して緑になる |
| **6** | 継続 | 人間レビューの指摘をルール化。CODEOWNERS を絞る | 全PR目視レビューを廃止 |

**フェーズ1〜2と並行して、人間レビューは残したまま指摘を記録してください。** これが L5 のチェックリストの原資になります。最初から人間を外さないことが、結果的に最短ルートになります。

---

## 10. AI生成コード特有の落とし穴と、対応する層

| 落とし穴 | 対応する層 | 具体策 |
|---|---|---|
| lint を `eslint-disable` で黙らせる | L1 | `no-unlimited-disable` / `require-description` / 差分での disable 増加検知 |
| `any` で型チェックを回避する | L1 | `no-explicit-any: error` |
| 存在しないパッケージを import | L2 | lockfile 固定＋OSV-Scanner＋新規依存の人間承認 |
| 認可チェックの欠落 | L2 / L5 | Semgrep カスタムルール＋チェックリスト |
| アサーションの緩いテストでカバレッジだけ稼ぐ | L4 | ミューテーションスコアで露見させる |
| 誤った実装をテストで固定化する | L4 / L5 | ミューテーションテスト＋別観点からのレビュー |
| 設計の一貫性が崩れ、重複が増える | L5 / 人間 | チェックリスト＋CODEOWNERS で設計レビューを残す |

---

## 付録：導入チェックリスト

### L1
- [ ] `packages/tsconfig/base.json` を作成し、各アプリから extends
- [ ] NestJS 側で `strictPropertyInitialization: false` を設定
- [ ] `packages/eslint-config` を作成し、抑制コメント系ルールを有効化
- [ ] `reportUnusedDisableDirectives: 'error'` を設定
- [ ] CI で `--max-warnings=0` を指定
- [ ] 既存コードのベースライン方針を決定

### L2
- [ ] Semgrep のルールセットを選定
- [ ] NestJS 認可の観点をカスタムルール化
- [ ] OSV-Scanner を lockfile に対して実行
- [ ] `--frozen-lockfile --ignore-scripts` を徹底
- [ ] 新規依存の検出と人間承認フローを整備

### L3
- [ ] Testcontainers による統合テスト基盤（Cloud Build の Docker 可否を確認）
- [ ] OpenAPI 型生成と drift 検出を CI に組み込み
- [ ] fast-check を導入し `FC_NUM_RUNS` を環境変数化
- [ ] Playwright は主要導線のみ PR、フルは nightly

### L4
- [ ] Jest / Vitest 各ランナーを導入
- [ ] `mutate` から module・エントリポイントを除外
- [ ] `scripts/stryker-diff.sh` を作成
- [ ] nightly で `--force` フル実行を設定
- [ ] 閾値は計測 → 現状値の少し下 → 段階的に引き上げ

### L5
- [ ] `.claude/skills/code-review/SKILL.md` を作成
- [ ] 「スタイル指摘をしない」制約を明記
- [ ] 非ブロック（`|| true`）で実行
- [ ] 生成に使うモデルと別系統のモデルを検討
- [ ] 人間の指摘を記録し、ルール化するサイクルを回す

---

*本手順書は調査レポート「人間のコードレビューを廃止・最小化しても品質を保証する開発方法」（第3版）に基づいています。各主張の根拠・出典は同レポートの出典一覧を参照してください。*
