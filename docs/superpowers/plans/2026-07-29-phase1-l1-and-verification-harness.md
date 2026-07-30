# Phase 1: L1（ESLint）とゲートスクリプト・検証ハーネス 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手順書 §2 の L1（型チェック＋Lint）をゲートとして成立させ、その検知能力を機械判定する検証ハーネスを作り、L1 系 6 ケースの判定結果を `verification/RESULTS.md` に記録する。

**Architecture:** ESLint 10 のフラットコンフィグを `packages/eslint-config` の共有ベース + パッケージごとの設定ファイルで構成する。ゲート本体は `scripts/gates/*.sh` に切り出し、exit code を 0（pass）/ 1（fail）/ 2（error）に正規化する。検証ハーネスは一時ブランチを切って `case.patch` を適用し、全ゲートを走らせて `expect.yml` と突き合わせる。

**Tech Stack:** ESLint 10.8.0 / typescript-eslint 8.65.0 / TypeScript 5.9.3（既存）/ bash / git

**設計書:** `docs/superpowers/specs/2026-07-29-multilayer-quality-gates-verification-design.md`
**前フェーズの申し送り:** `docs/superpowers/phase0-findings.md` の §3「Phase 1」

---

## Global Constraints

### バージョン固定表

すべて完全固定（`^` や `~` を付けない）。検証結果の再現性を担保するため。

| パッケージ | バージョン | 配置 |
|---|---|---|
| `eslint` | `10.8.0` | root（devDependencies） |
| `typescript-eslint` | `8.65.0` | `packages/eslint-config`（dependencies） |
| `@eslint/js` | `10.0.1` | `packages/eslint-config`（dependencies） |
| `@eslint-community/eslint-plugin-eslint-comments` | `4.7.2` | `packages/eslint-config`（dependencies） |
| `eslint-plugin-react-hooks` | `7.1.1` | `apps/web`（devDependencies） |
| `eslint-plugin-jsx-a11y` | `6.10.2` | `apps/web`（devDependencies） |

既存の固定（変更しない）：`typescript` `5.9.3`、`prisma` / `@prisma/client` `6.19.3`、`turbo` `2.10.7`。

**`typescript` は 5.9.3 から動かさない。** `typescript-eslint@8.65.0` の peerDependency は `typescript: ">=4.8.4 <6.1.0"` で、`ts-jest@29.4.12` は `">=4.3 <7"`。交差の上限は 6.0.x であり、最新の 7.0.2 は使えない。

### 依存の配置方針（手順書からの逸脱を含む）

手順書 §2.4 は `pnpm add -Dw` で全プラグインをワークスペースルートに入れる。**本計画は共有設定が使うものを `packages/eslint-config` の `dependencies` に置く。** ルートに置いても Node の上位ディレクトリ探索で解決はできるが、暗黙のホイスティングに依存する形になり、`packages/eslint-config` を単体で見たときに何が必要か読めない。`eslint` 本体だけはルートに置く（`pnpm eslint .` をルートから実行するため）。

### 設定ファイル名は `.mjs` に統一する（重要）

**ESLint のフラットコンフィグを `eslint.config.js` という名前で書けるのは、そのパッケージが `"type": "module"` のときだけである。** `apps/web` は `"type": "module"` なので手順書 §2.4 の `apps/web/eslint.config.js` は動くが、`apps/api`（NestJS / CommonJS）とワークスペースルートは `"type": "module"` ではないため、同じ名前で ESM 構文を書くと実行時に落ちる。

本計画では **すべて `eslint.config.mjs`** に統一する。`packages/eslint-config` は純粋な ESM パッケージなので `package.json` に `"type": "module"` を設定し、エントリは `index.js` とする。

> **Phase 6 の検証レポート項目**：手順書 §2.4 の `apps/web/eslint.config.js` は Vite アプリ（`type: module`）でのみ成立する。NestJS 側に同じ名前で書くと壊れる点に手順書は触れていない。

### ESLint 10 の設定探索の挙動（実測済み）

**ESLint 10 は lint 対象ファイルから上方向に設定ファイルを探索し、見つかった設定が上位の設定を「置き換える」（マージしない）。** スクラッチ環境で実測した。ルートに `eqeqeq: error`、`apps/web/eslint.config.mjs` に `no-console: error` を置いてルートから `eslint .` を実行すると、`apps/web` 配下のファイルには `no-console` だけが適用され `eqeqeq` は適用されなかった。

したがって**各パッケージの設定ファイルが自分で共有ベースを import する必要がある**（手順書 §2.4 の `import base from '@repo/eslint-config'` の形が正しい）。

### 手順書に無い設定ファイル（仮説 6 の確認結果）

手順書 §2.4 は `packages/eslint-config/index.js` と `apps/web/eslint.config.js` しか示していない。上記の探索挙動から、`pnpm eslint .` をルートで成立させるには次の 2 つが追加で必要である。

- **ワークスペースルートの `eslint.config.mjs`** — `packages/shared` などパッケージ固有設定を持たない場所のファイルを担当する。無いと `eslint .` が設定ファイル未検出で失敗する
- **`apps/api/eslint.config.mjs`** — NestJS 固有設定（デコレータ、CommonJS）を当てる

**仮説 6 は確認済みとして扱う。** Task 1・Task 2 でこの 2 ファイルを作り、Phase 6 レポートに「手順書 §2.4 は記述漏れ」として記録する。

### `no-unused-disable` は入れない（仮説 7 の確認結果）

手順書 §2.4 は `@eslint-community/eslint-comments/no-unused-disable: 'error'` を推奨しているが、**本計画では入れない。** スクラッチ環境での実測結果は次のとおり。

| 設定 | 重大度 | `--max-warnings=0` あり | なし |
|---|---|---|---|
| 何も設定しない（ESLint 10 の既定） | warn | exit 1 | exit 0 |
| プラグインの `no-unused-disable` のみ | warn（既定と同一出力） | exit 1 | exit 0 |
| `linterOptions.reportUnusedDisableDirectives: 'error'` | error | exit 1 | exit 1 |

プラグインルールを有効にしても既定と同じ warn しか出ず、**何も追加していない（no-op）**。さらに `no-unused-disable` は **4.7.0 で deprecated、5.0.0 で削除予定**で、非推奨メッセージ自体が「ESLint 組み込みの `linterOptions` を使え」と指示している。

一方 `linterOptions.reportUnusedDisableDirectives: 'error'` は意味がある。ESLint 10 の既定は `warn` なので、`--max-warnings=0` を付け忘れた実行では見逃す。手順書が「`linterOptions` で error 化」と「CI で `--max-warnings=0`」の両方を要求しているのは正しい。

> **Phase 6 の検証レポート項目**：設計書 §7 の仮説 7 は「機能重複で二重報告になる」としていたが、**実測では二重報告は起きない**。実際の問題は「非推奨かつ no-op のルールを手順書が推奨している」ことだった。仮説の記述を修正する。

### 記述ルール

- コメント・エラーメッセージ・`RESULTS.md` の記述は日本語で書く。
- シェルスクリプトは `#!/usr/bin/env bash` と `set -euo pipefail` で始める。
- `verification/cases/` 配下のディレクトリ名は設計書 §9 の ID をそのまま使う。

---

## File Structure

### ESLint 設定

| ファイル | 責務 |
|---|---|
| `packages/eslint-config/package.json` | `@repo/eslint-config`。`"type": "module"`、プラグインを dependencies に持つ |
| `packages/eslint-config/index.js` | 全パッケージ共通のベース設定。手順書 §2.4 のルール群 + 抑制コメント制御 |
| `eslint.config.mjs`（ルート） | パッケージ固有設定を持たない場所（`packages/shared` 等）とルート直下のファイルを担当 |
| `apps/api/eslint.config.mjs` | ベース + NestJS 固有（デコレータ、`prisma/seed.ts` の扱い） |
| `apps/web/eslint.config.mjs` | ベース + React Hooks / jsx-a11y / `no-restricted-imports` |

### ゲートスクリプト

| ファイル | 責務 |
|---|---|
| `scripts/gates/_lib.sh` | exit code 正規化の共通関数。全ゲートスクリプトが source する |
| `scripts/gates/l2-install.sh` | `pnpm install --frozen-lockfile --ignore-scripts` + `prisma generate` |
| `scripts/gates/l1-typecheck.sh` | `pnpm turbo typecheck` |
| `scripts/gates/l1-lint.sh` | `pnpm eslint . --max-warnings=0` |

### 検証ハーネス

| ファイル | 責務 |
|---|---|
| `verification/run-case.sh` | 1 ケースを実行：ブランチ作成 → パッチ適用 → ゲート実行 → 判定 → 後片付け |
| `verification/run-all.sh` | 全ケースを `run-case.sh` に流し、`RESULTS.md` を再生成する |
| `verification/lib/judge.mjs` | ゲートの実測結果と `expect.yml` を突き合わせ、判定行を出力する |
| `verification/RESULTS.md` | 検証結果マトリクス（`run-all.sh` が生成） |
| `verification/cases/<CASE-ID>/case.patch` | 欠陥を注入する差分 |
| `verification/cases/<CASE-ID>/expect.yml` | 期待結果（機械可読） |

**`judge.mjs` を Node で書く理由**：`expect.yml` の読み取りと突き合わせを bash でやると YAML パースを自作することになる。Node は既にツールチェーンにあり、`expect.yml` を厳密な形式（後述）に限定すれば依存を追加せず 40 行程度で書ける。判定ロジックはハーネスの中核なので、テストできる形にしておく。

---

## Task 1: ESLint 共通設定パッケージとルート設定

**Files:**
- Create: `packages/eslint-config/package.json`
- Create: `packages/eslint-config/index.js`
- Create: `eslint.config.mjs`（ワークスペースルート）
- Modify: `package.json`（ルート。`eslint` を devDependencies に追加、`lint` スクリプトを追加）

**Interfaces:**
- Consumes: 既存の `packages/tsconfig`（`@repo/tsconfig`）、既存のワークスペース構成
- Produces:
  - `@repo/eslint-config` の default export = ESLint フラットコンフィグの配列。各パッケージの設定は `import base from '@repo/eslint-config'` して `[...base, /* 固有設定 */]` の形で使う
  - ルートの `pnpm lint` スクリプト = `eslint . --max-warnings=0`

- [ ] **Step 1: `eslint` をルートに追加**

```bash
pnpm add -Dw eslint@10.8.0
```

`package.json` の `devDependencies` が `eslint: "10.8.0"`（`^` なし）になっていることを確認する。`pnpm add` は既定で `^` を付けるので、付いていたら手で外して `pnpm install` し直す。

- [ ] **Step 2: ルート `package.json` に `lint` スクリプトを追加**

`scripts` に 1 行追加する。他のフィールドは変更しない。

```json
    "lint": "eslint . --max-warnings=0",
```

`build` / `typecheck` / `test` と違い turbo を経由しない。ESLint 10 は lint 対象ファイルから設定を探索するので、ルートから 1 回走らせれば全パッケージを見る。turbo に分割すると設定探索の単位とタスクの単位がずれて混乱するため、意図的に単一コマンドにする。

- [ ] **Step 3: `packages/eslint-config/package.json` を作成**

```json
{
  "name": "@repo/eslint-config",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "main": "./index.js",
  "exports": { ".": "./index.js" },
  "dependencies": {
    "@eslint-community/eslint-plugin-eslint-comments": "4.7.2",
    "@eslint/js": "10.0.1",
    "typescript-eslint": "8.65.0"
  }
}
```

- [ ] **Step 4: `packages/eslint-config/index.js` を作成**

手順書 §2.4 のルール群を入れる。ただし `no-unused-disable` は入れない（Global Constraints 参照）。

```js
import comments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

/**
 * 全パッケージ共通の ESLint ベース設定。
 *
 * 各パッケージの eslint.config.mjs は必ずこれを import して先頭に展開する。
 * ESLint 10 は対象ファイルから上方向に設定ファイルを探索し、見つかった設定で
 * 上位の設定を「置き換える」ため、ベースを継承するには各設定が自分で import する
 * 必要がある。
 */
export default tseslint.config(
  {
    // 生成物・依存はどのパッケージでも対象外
    ignores: ['**/dist/**', '**/coverage/**', '**/node_modules/**', '**/.turbo/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  comments.recommended,
  {
    linterOptions: {
      // 効いていない抑制コメント（＝負債）を検出する。
      // ESLint 10 の既定は warn なので、明示的に error へ上げる。
      reportUnusedDisableDirectives: 'error',
    },
    languageOptions: {
      parserOptions: { projectService: true },
    },
    rules: {
      // --- 手順書 §2.4 の厳選ルール ---
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unnecessary-condition': 'error',
      eqeqeq: ['error', 'always'],
      'no-console': 'error',

      // --- 抑制コメントを締める ---
      '@eslint-community/eslint-comments/no-unlimited-disable': 'error',
      '@eslint-community/eslint-comments/require-description': 'error',
    },
  },
  {
    // 設定ファイル自身は型情報付きルールの対象外にする。
    // tsconfig のプロジェクトに含まれない .js/.mjs に型情報付きルールを当てると
    // 「どのプロジェクトにも属さない」エラーになる。
    files: ['**/*.js', '**/*.mjs', '**/*.cjs'],
    extends: [tseslint.configs.disableTypeChecked],
  },
);
```

`no-unused-disable` を入れていないのは意図的である（Global Constraints 参照）。`require-description` は `comments.recommended` に含まれないので明示的に有効化する。

- [ ] **Step 5: ルート `eslint.config.mjs` を作成**

パッケージ固有設定を持たない場所（`packages/shared`、`packages/tsconfig`、ルート直下）を担当する。

```js
import base from '@repo/eslint-config';

export default [
  ...base,
  {
    // 検証ハーネスとゲートスクリプトは bash / 単体 Node スクリプトで、
    // どの tsconfig プロジェクトにも属さない
    ignores: ['verification/lib/**', 'docs/**'],
  },
];
```

**`apps/**` を ignores に入れてはいけない。** `files` を伴わない単独の `ignores` は ESLint の**グローバル ignore** であり、ディレクトリ走査そのものを止める。`apps/**` を入れると `pnpm eslint .` が `apps/` 配下を 1 件も検査せず、`--max-warnings=0` が通ってしまう — **L1 ゲートが何も守らない状態**になる。実測では走査対象が 3 ファイル（`apps/` 配下 0 件）まで縮んだ。

`apps/api` と `apps/web` は自分の設定ファイルを持つが、それは「ルート設定から除外する」ことでは表現しない。ESLint 10 はファイルごとに設定を探索し、見つかった設定が上位を置き換えるので、除外を書く必要がそもそも無い。

> **Phase 6 の検証レポート項目**：`ignores` を「このディレクトリは別の設定が担当する」という**責務の注記代わりに使ってはいけない**。グローバル ignore は走査を止めるため、ゲートが空振りする。手順書 §2.4 は設定の分割方法を示すだけで、ルート設定側で何を書くべきか / 書いてはいけないかに触れていない。

`verification/lib/**` を除外する理由は、Task 4 で作る `judge.mjs` が型チェック対象の tsconfig を持たないためである。Task 4 でここを見直す。

- [ ] **Step 6: `@repo/eslint-config` をルートに参照させる**

ルート `package.json` の `devDependencies` に追加する。

```json
    "@repo/eslint-config": "workspace:*",
```

- [ ] **Step 7: インストールしてルート設定だけで lint が動くことを確認**

```bash
pnpm install
pnpm eslint packages/shared --max-warnings=0
```

Expected: exit 0、出力なし。`packages/shared/src/index.ts` は定数と型だけなので違反は無い。

もし「どのプロジェクトにも属さない」系のエラーが出た場合は、`packages/shared/tsconfig.json` の `include` が `src/**/*.ts` を含んでいることを確認する（Phase 0 で設定済み）。それでも解決しない場合は**設定を緩めずに報告する** — `projectService: true` がモノレポで機能するかは検証対象の一部である。

- [ ] **Step 8: コミット**

```bash
git add packages/eslint-config eslint.config.mjs package.json pnpm-lock.yaml
git commit -m "feat: ESLint 共通設定パッケージとルート設定を追加"
```

---

## Task 2: 各アプリの ESLint 設定と既存コードの違反解消

**Files:**
- Create: `apps/api/eslint.config.mjs`
- Create: `apps/web/eslint.config.mjs`
- Modify: `apps/api/package.json`（`@repo/eslint-config` を devDependencies に追加）
- Modify: `apps/web/package.json`（`@repo/eslint-config`・`eslint-plugin-react-hooks`・`eslint-plugin-jsx-a11y` を devDependencies に追加）
- Modify: 既存ソース（lint 違反が出たファイル。候補は後述）

**Interfaces:**
- Consumes: `@repo/eslint-config` の default export（Task 1）
- Produces: `pnpm lint`（= `eslint . --max-warnings=0`）が exit 0 になる状態

- [ ] **Step 1: `apps/api/eslint.config.mjs` を作成**

```js
import base from '@repo/eslint-config';

export default [
  ...base,
  {
    ignores: ['dist/**', 'coverage/**', 'reports/**'],
  },
  {
    // Prisma のシードスクリプトは CLI から手で叩く運用スクリプトであり、
    // 実行結果を標準出力に出すことが目的なので no-console を無効にする。
    // アプリ本体（src/**）には適用しない。
    files: ['prisma/**/*.ts'],
    rules: { 'no-console': 'off' },
  },
];
```

`prisma/**` で `no-console` を切るのは、Phase 0 の申し送り #1 への対応である。もう一つの選択肢は `eslint-disable-next-line` を `require-description` 付きで書くことだったが、`seed.ts` は 3 箇所で `console` を使い、いずれも「投入結果を人が読むための出力」という同じ理由なので、ファイル単位で切るほうが抑制コメントを撒くより読みやすい。**`src/**` には適用しないので、アプリ本体の `no-console` は効いたままである。**

- [ ] **Step 2: `apps/web/eslint.config.mjs` を作成**

手順書 §2.4 の Web 側設定に、`e2e` と設定ファイルの扱いを補う。

```js
import base from '@repo/eslint-config';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  ...base,
  {
    ignores: ['dist/**', 'coverage/**', 'reports/**', '.playwright-mcp/**'],
  },
  reactHooks.configs['recommended-latest'],
  jsxA11y.flatConfigs.recommended,
  {
    rules: {
      // warn ではなく error にする
      'react-hooks/exhaustive-deps': 'error',
      // Web から API の内部実装を直接 import させない
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            { group: ['**/apps/api/src/**'], message: '共有は packages/shared 経由で' },
          ],
        },
      ],
    },
  },
];
```

- [ ] **Step 3: 依存を追加**

```bash
pnpm add -D --filter api @repo/eslint-config@workspace:*
pnpm add -D --filter web @repo/eslint-config@workspace:* eslint-plugin-react-hooks@7.1.1 eslint-plugin-jsx-a11y@6.10.2
pnpm install
```

追加後、両方の `package.json` でバージョンに `^` が付いていないことを確認する。付いていたら手で外して `pnpm install` し直す。

- [ ] **Step 4: lint を実行して違反の全量を把握する**

```bash
pnpm eslint . --max-warnings=0 > /tmp/lint-baseline.txt 2>&1; echo "EXIT=$?"
cat /tmp/lint-baseline.txt
```

この時点では **exit 1 になるのが正常** である。出力を全部残しておく。

- [ ] **Step 5: 違反を分類して対処する**

出た違反を次の方針で処理する。**「とりあえず抑制する」ことは禁止。**

| 想定される違反 | 対処 |
|---|---|
| `apps/api/src/main.ts` の `console.error` | `no-console` に該当する。起動失敗を人に見せる唯一の手段なので、`eslint-disable-next-line no-console -- 起動失敗はログ以外に伝える手段が無い` を書く。`require-description` が有効なので `--` 以降の理由は必須 |
| `apps/api/prisma/seed.ts` の `console` | Step 1 の `files: ['prisma/**/*.ts']` ブロックで既に無効化済み。ここで違反が出るなら設定が効いていないので調べる |
| 型情報付きルールの「どのプロジェクトにも属さない」エラー | 対象ファイルを該当パッケージの tsconfig の `include` に加える。`disableTypeChecked` を広げて回避してはいけない |
| `@typescript-eslint/no-unnecessary-condition` の誤検知 | 型が `T \| null` なら必要な条件なので違反にならないはず。出た場合は型定義側を見直す |
| 上記以外 | **勝手に直さず報告する。** 手順書のルールセットが既存コードに何を要求するかは検証データそのものである |

対処のたびに `pnpm eslint . --max-warnings=0` を回して残りを確認する。

- [ ] **Step 6: lint が緑になることを確認**

```bash
pnpm eslint . --max-warnings=0; echo "EXIT=$?"
```

Expected: `EXIT=0`、出力なし。

- [ ] **Step 7: 既存のテストとビルドが壊れていないことを確認**

```bash
pnpm turbo build typecheck test
```

Expected: 9 タスク成功、23 テスト（api 13 / web 10）。lint 対応でソースを触っているので必須。

- [ ] **Step 8: `no-console` がアプリ本体では効いていることを確認**

`prisma/**` の除外がアプリ本体に漏れていないことを確かめる。一時ファイルで検証し、確認後に削除する。

```bash
printf 'console.log("probe");\nexport const probe = 1;\n' > apps/api/src/__probe.ts
pnpm eslint apps/api/src/__probe.ts 2>&1 | grep -c 'no-console'
rm -f apps/api/src/__probe.ts
```

Expected: `1`（`no-console` が 1 件報告される）。`0` なら除外が広すぎるので `apps/api/eslint.config.mjs` を見直す。

- [ ] **Step 9: コミット**

```bash
git add apps/api apps/web pnpm-lock.yaml
git commit -m "feat: apps/api と apps/web の ESLint 設定を追加し既存の違反を解消"
```

---

## Task 3: ゲートスクリプトと exit code の正規化

**Files:**
- Create: `scripts/gates/_lib.sh`
- Create: `scripts/gates/l2-install.sh`
- Create: `scripts/gates/l1-typecheck.sh`
- Create: `scripts/gates/l1-lint.sh`
- Test: `scripts/gates/gates.test.sh`

**Interfaces:**
- Consumes: ルートの `lint` スクリプト（Task 1）、既存の `turbo typecheck`
- Produces:
  - 各ゲートスクリプトは引数を取らず、リポジトリルートから実行される
  - exit code の契約: `0` = pass（ゲート通過）、`1` = fail（ゲートがブロック＝欠陥を検出）、`2` = error（ツールが実行できなかった）
  - `_lib.sh` が提供する関数:
    - `gate_require_repo` — git リポジトリの中でなければ exit 2（移動はしない）
    - `gate_require_cmd <コマンド名>` — 無ければ exit 2
    - `gate_finish <生 exit code> <fail とみなす code のリスト>` — 正規化して exit する
  - **ゲートスクリプトはどのカレントディレクトリから呼んでも動く。** 各スクリプトが冒頭で自分の位置を起点にリポジトリルートへ移動するため。ハーネスも CI もこれに依存する
  - 全ゲートスクリプトの冒頭は次の定型で始まる。`_lib.sh` を相対パスで source するため、**`cd` が source より先でなければならない**

```bash
# スクリプト自身の位置からリポジトリルートへ移動する。
# PATH が壊れていても効くよう外部コマンド（dirname）を使わない。
_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh
```

- [ ] **Step 1: 失敗するテストを書く**

`scripts/gates/gates.test.sh`:

```bash
#!/usr/bin/env bash
# ゲートスクリプトの exit code 契約を検証する。
# 0 = pass / 1 = fail / 2 = error
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

FAILURES=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'ok   %s (exit %s)\n' "$label" "$actual"
  else
    printf 'FAIL %s: expected exit %s, got %s\n' "$label" "$expected" "$actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- クリーンなツリーでは全ゲートが pass ---
./scripts/gates/l1-typecheck.sh >/dev/null 2>&1
check 'l1-typecheck はクリーンなツリーで pass' 0 "$?"

./scripts/gates/l1-lint.sh >/dev/null 2>&1
check 'l1-lint はクリーンなツリーで pass' 0 "$?"

# --- 必要なコマンドが無いときは error(2) ---
# PATH から pnpm を外す。pnpm は volta / homebrew などルート外に入るので
# /usr/bin:/bin に絞れば消える。一方 env と bash はここに居るので、
# スクリプト自体は起動できて gate_require_cmd まで到達する。
# PATH=/nonexistent は使えない。`#!/usr/bin/env bash` の bash 解決ごと壊れ、
# ゲートが起動する前にシェルが 127 で落ちるため、ゲートの正規化を検証できない。
( PATH=/usr/bin:/bin ./scripts/gates/l1-lint.sh ) >/dev/null 2>&1
check 'l1-lint は pnpm が無いとき error' 2 "$?"

( PATH=/usr/bin:/bin ./scripts/gates/l1-typecheck.sh ) >/dev/null 2>&1
check 'l1-typecheck は pnpm が無いとき error' 2 "$?"

# --- どのカレントディレクトリからでも動く ---
# ゲートは自分でリポジトリルートへ移動するので、呼び出し位置に依存しない。
# ハーネスと CI がこれに依存する。
GATE_ABS="$PWD/scripts/gates"
( cd / && "$GATE_ABS/l1-lint.sh" ) >/dev/null 2>&1
check 'l1-lint は / から呼んでも pass' 0 "$?"

( cd / && "$GATE_ABS/l1-typecheck.sh" ) >/dev/null 2>&1
check 'l1-typecheck は / から呼んでも pass' 0 "$?"

TOTAL=6
if [ "$FAILURES" -eq 0 ]; then
  printf '\n全 %s 件のチェックが成功しました\n' "$TOTAL"
  exit 0
fi
printf '\n%s / %s 件のチェックが失敗しました\n' "$FAILURES" "$TOTAL"
exit 1
```

`exit 1`（fail）の検証はここに入れない。実際の欠陥を注入する必要があり、それは Task 5 の検証ケースで行う。ここでは **pass 経路・error 経路・呼び出し位置非依存** の 3 点を固める。

**この割り切りには代償がある。** fail 経路を試さないので、`gate_finish` に渡す「fail とみなす code」が間違っていても 6 件すべて成功する。実際に Phase 1 でこれが起きた（`l1-typecheck.sh` が turbo の code を取り違えていたが `gates.test.sh` は修正前も修正後も 6/6 成功だった）。Task 5 の検証ケースが唯一の検出手段である。

- [ ] **Step 2: テストが失敗することを確認**

```bash
chmod +x scripts/gates/gates.test.sh
./scripts/gates/gates.test.sh
```

Expected: FAIL。`./scripts/gates/l1-typecheck.sh: No such file or directory` になり、6 件すべてが期待外の exit code を報告する。

- [ ] **Step 3: `scripts/gates/_lib.sh` を作成**

```bash
#!/usr/bin/env bash
# ゲートスクリプト共通のヘルパ。
#
# exit code の契約:
#   0 = pass  ゲート通過
#   1 = fail  ゲートがブロックした（＝欠陥を検出した）
#   2 = error ツールが実行できなかった（判定不能）
#
# 各ツールの生 exit code は多様なので（Semgrep は 1=findings/2=error、
# ESLint は 1=lint error/2=config error など）、この 3 値へ明示的に写像する。
# error を fail と誤って記録すると「Docker が起動していないだけ」を
# 「欠陥を検出した」と読み違えるため、区別が最重要である。

GATE_PASS=0
GATE_FAIL=1
GATE_ERROR=2

# 指定コマンドが使えなければ error で終了する
gate_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'gate error: コマンドが見つかりません: %s\n' "$cmd" >&2
    exit "$GATE_ERROR"
  fi
}

# git リポジトリの中にいることを確認する。移動はしない（呼び出し側が済ませている）。
gate_require_repo() {
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    printf 'gate error: git リポジトリの中で実行してください（現在: %s）\n' "$PWD" >&2
    exit "$GATE_ERROR"
  fi
}

# 生 exit code を 3 値へ正規化して終了する。
#   $1        生 exit code
#   $2 以降   fail とみなす生 exit code（列挙）
# 列挙に無い非ゼロは error とみなす。
gate_finish() {
  local raw="$1"
  shift
  if [ "$raw" -eq 0 ]; then
    exit "$GATE_PASS"
  fi
  local code
  for code in "$@"; do
    if [ "$raw" -eq "$code" ]; then
      exit "$GATE_FAIL"
    fi
  done
  printf 'gate error: 予期しない exit code: %s\n' "$raw" >&2
  exit "$GATE_ERROR"
}
```

- [ ] **Step 4: `scripts/gates/l1-typecheck.sh` を作成**

```bash
#!/usr/bin/env bash
# L1: 型チェック（手順書 §2.5）
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm

pnpm turbo typecheck
# turbo は子プロセスの exit code をそのまま透過する。tsc は型エラーで 2 を返すので
# fail は 2 である。turbo 自身の異常（タスク名が無い / turbo.json が壊れている）は 1 なので、
# 1 は error 側に残す。ここを `gate_finish "$?" 1` にすると型エラーが「ツールが実行できなかった」
# と記録され、逆に turbo の設定ミスが「欠陥を検出した」になる。実測で確認済み:
#   型エラーあり → 2 / 存在しないタスク名 → 1 / 壊れた turbo.json → 1
gate_finish "$?" 2
```

`set -e` を使っていないのは、`pnpm turbo typecheck` の非ゼロ exit を捕まえて `gate_finish` に渡す必要があるためである。`set -e` があるとその時点で終了してしまう。

- [ ] **Step 5: `scripts/gates/l1-lint.sh` を作成**

```bash
#!/usr/bin/env bash
# L1: Lint（手順書 §2.5）
#
# --max-warnings=0 が要点。warn は CI では実質無視され溜まる一方になるため、
# ゲートにするなら警告ゼロを強制する（手順書 §2.5）。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm

pnpm exec eslint . --max-warnings=0
# ESLint: 1 = lint エラーまたは警告数超過（fail）、2 = 設定エラー（error）
gate_finish "$?" 1
```

`pnpm exec eslint` を直接呼ぶのは、`pnpm lint`（`package.json` のスクリプト）経由だと pnpm がスクリプト失敗時に自前の exit code を被せることがあり、ESLint の 1 と 2 の区別が失われるためである。

- [ ] **Step 6: `scripts/gates/l2-install.sh` を作成**

L2 のゲートだが、ハーネスが他のゲートより先に実行する必要があるため Phase 1 で作る。

```bash
#!/usr/bin/env bash
# L2: 依存インストール（手順書 §3.3 ①）
#
# lockfile を絶対とし、インストールスクリプトを無効化する。
# --ignore-scripts のため Prisma Client の生成は走らないので、明示的に生成する。
# Phase 0 の実測では、--ignore-scripts の有無に関わらず pnpm workspace では
# Prisma の postinstall がスキーマを発見できずスタブを生成する。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm

pnpm install --frozen-lockfile --ignore-scripts
raw=$?
if [ "$raw" -ne 0 ]; then
  # lockfile と package.json の不整合（存在しないパッケージの追加など）は fail
  gate_finish "$raw" 1
fi

pnpm --filter api exec prisma generate
gate_finish "$?" 1
```

- [ ] **Step 7: 実行権限を付けてテストが通ることを確認**

```bash
chmod +x scripts/gates/*.sh
./scripts/gates/gates.test.sh
```

Expected: `全 6 件のチェックが成功しました`、exit 0。

- [ ] **Step 8: `l2-install.sh` を単体で確認**

`gates.test.sh` には入れていない（インストールは副作用が大きく、テストのたびに走らせたくない）。手で 1 回確認する。

```bash
./scripts/gates/l2-install.sh; echo "EXIT=$?"
```

Expected: `EXIT=0`。`--ignore-scripts` を付けているので postinstall は走らず、明示した `prisma generate` が `Prisma schema loaded from prisma/schema.prisma` を出す。

続けて、生成された Client がスタブでないことを確認する。

```bash
pnpm turbo typecheck
```

Expected: 成功。`TS2694: ... has no exported member 'OrderGetPayload'` が出たら `prisma generate` が効いていない。

- [ ] **Step 9: コミット**

```bash
git add scripts/gates
git commit -m "feat: ゲートスクリプトと exit code 正規化を追加"
```

---

## Task 4: 検証ハーネス

**Files:**
- Create: `verification/lib/judge.mjs`
- Test: `verification/lib/judge.test.mjs`
- Create: `verification/run-case.sh`
- Create: `verification/run-all.sh`
- Modify: `eslint.config.mjs`（ルート。`verification/lib/**` の扱いを見直す）

**Interfaces:**
- Consumes: `scripts/gates/*.sh` の exit code 契約（Task 3）
- Produces:
  - `verification/run-case.sh <CASE-ID>` — 1 ケースを実行し、結果を 1 行の TSV で標準出力に出す
  - `verification/run-all.sh` — 全ケースを実行し `verification/RESULTS.md` を生成する
  - `judge.mjs` の CLI: `node verification/lib/judge.mjs <expect.yml のパス> <actual.tsv のパス>` → 判定結果を JSON で標準出力
  - `expect.yml` の形式（後述のとおり厳密に限定する）
  - `actual.tsv` の形式: 1 行 1 ゲート、`<ゲート名>\t<正規化 exit code>\t<出力の 1 行要約>`
  - `judge()` の戻り値: `{ claimVerdict, configVerdict, errored, blockedBy, blockingLayers, mismatches }`

### 判定は 2 系統ある（重要）

設計書 §8.4 は「単に『ゲートが赤くなった』ではなく **『主張どおりの層が捕まえたか』を判定する**」と規定している。これを満たすため `judge()` は独立した 2 つの判定を返す。

| 判定 | 何を比べるか | 何のためか |
|---|---|---|
| `claimVerdict` | `claimed_layer`（手順書の主張）と、実際に止めたゲートが属する層 | **検証の本題。** `RESULTS.md` の判定列に出る |
| `configVerdict` | `expect` の各ゲートの pass/fail と実測 | 自分のゲート設定の回帰検出。将来 Phase で設定が壊れたら気づける |

`claimVerdict` の値は `match`（主張どおりの層が止めた）/ `mismatch`（別の層が止めた）/ `not-caught`（どのゲートも止めなかった）/ `inconclusive`（error があった）。

層はゲート名の接頭辞から導く（`l1-lint` → `L1`、`l2-install` → `L2`）。

**`expect` は実測に合わせて更新してよいが、`claimed_layer` は絶対に変えてはいけない。** `expect` は「自分のゲートがどう振る舞うか」のスナップショットであり、初回は実測で確定させるのが正しい。`claimed_layer` は手順書 §10 の主張そのもので、これが検証対象である。ここを実測に合わせて書き換えると判定が恒真になり、ハーネスが何も検証しなくなる。

### `expect.yml` の形式

`judge.mjs` は YAML の完全なパーサを持たない。次の形に限定する。

```yaml
id: L1-02-explicit-any
pitfall: any で型チェックを回避する
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: fail
expect_detection:
  l5-ai-review: false
```

制約：

- トップレベルは `id` / `pitfall` / `claimed_layer` / `expect` / `expect_detection` のみ
- `expect` と `expect_detection` の子はインデント 2 スペース、値はそれぞれ `pass` / `fail`、`true` / `false`
- コメント行（`#` で始まる）と空行は無視する
- 値に引用符・複数行・入れ子は使わない

Phase 1 では `expect_detection` を使うゲート（`l2-new-deps` / `l5-ai-review`）がまだ無いため、キーの読み取りだけ実装して判定はスキップする。

- [ ] **Step 1: `judge.mjs` の失敗するテストを書く**

`verification/lib/judge.test.mjs`:

```js
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { judge, parseActual, parseExpect } from './judge.mjs';

function writeTemp(name, content) {
  const dir = mkdtempSync(join(tmpdir(), 'judge-'));
  const path = join(dir, name);
  writeFileSync(path, content, 'utf8');
  return path;
}

const EXPECT_YML = `id: L1-02-explicit-any
pitfall: any で型チェックを回避する
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: fail
`;

test('parseExpect は限定形式の YAML を読める', () => {
  const parsed = parseExpect(writeTemp('expect.yml', EXPECT_YML));
  assert.equal(parsed.id, 'L1-02-explicit-any');
  assert.equal(parsed.pitfall, 'any で型チェックを回避する');
  assert.equal(parsed.claimedLayer, 'L1');
  assert.deepEqual(parsed.expect, {
    'l2-install': 'pass',
    'l1-typecheck': 'pass',
    'l1-lint': 'fail',
  });
});

test('parseExpect はコメント行と空行を無視する', () => {
  const withNoise = `# これはコメント\nid: X\n\npitfall: p\nclaimed_layer: L1\nexpect:\n  # 途中のコメント\n  l1-lint: fail\n`;
  const parsed = parseExpect(writeTemp('expect.yml', withNoise));
  assert.deepEqual(parsed.expect, { 'l1-lint': 'fail' });
});

// 以下 3 件は「構造は正しいが中身が不正」なケース。黙って通ると判定が
// 恒真／恒偽になり、ハーネスが何も検証しなくなる。
test('parseExpect は claimed_layer が L1〜L5 でなければ throw する', () => {
  const lower = `id: X\npitfall: p\nclaimed_layer: l1\nexpect:\n  l1-lint: fail\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', lower)), /claimed_layer が不正/);
  const missing = `id: X\npitfall: p\nexpect:\n  l1-lint: fail\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', missing)), /claimed_layer が不正/);
});

test('parseExpect は expect が空なら throw する', () => {
  const empty = `id: X\npitfall: p\nclaimed_layer: L1\nexpect:\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', empty)), /expect が空/);
});

test('parseExpect は expect の値が pass/fail 以外なら throw する', () => {
  const quoted = `id: X\npitfall: p\nclaimed_layer: L1\nexpect:\n  l1-lint: "fail"\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', quoted)), /pass か fail のみ/);
  const typo = `id: X\npitfall: p\nclaimed_layer: L1\nexpect:\n  l1-lint: faill\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', typo)), /pass か fail のみ/);
});

test('parseActual は TSV を読める', () => {
  const tsv = 'l2-install\t0\tok\nl1-typecheck\t0\tok\nl1-lint\t1\t3 problems\n';
  assert.deepEqual(parseActual(writeTemp('actual.tsv', tsv)), {
    'l2-install': { code: 0, summary: 'ok' },
    'l1-typecheck': { code: 0, summary: 'ok' },
    'l1-lint': { code: 1, summary: '3 problems' },
  });
});

test('judge は主張どおりの層が止めたとき claimVerdict を match とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'fail', 'l1-typecheck': 'pass' } },
    { 'l1-lint': { code: 1, summary: '' }, 'l1-typecheck': { code: 0, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'match');
  assert.equal(result.configVerdict, 'match');
  assert.deepEqual(result.blockedBy, ['l1-lint']);
  assert.deepEqual(result.blockingLayers, ['L1']);
});

test('judge は主張と別の層が止めたとき claimVerdict を mismatch とする', () => {
  // 手順書は L2（OSV-Scanner）が止めると主張しているが、実際に止めたのは install だけ
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L4', expect: { 'l2-install': 'fail' } },
    { 'l2-install': { code: 1, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'mismatch');
  assert.deepEqual(result.blockingLayers, ['L2']);
});

test('judge はどのゲートも止めなかったとき claimVerdict を not-caught とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'pass' } },
    { 'l1-lint': { code: 0, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'not-caught');
  assert.deepEqual(result.blockedBy, []);
});

test('judge は expect と実測がずれたとき configVerdict を mismatch とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'fail' } },
    { 'l1-lint': { code: 0, summary: '' } },
  );
  assert.equal(result.configVerdict, 'mismatch');
  assert.deepEqual(result.mismatches, [{ gate: 'l1-lint', expected: 'fail', actual: 'pass' }]);
});

test('judge は error(2) を含むケースを両方 inconclusive とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'fail' } },
    { 'l1-lint': { code: 2, summary: 'docker が起動していない' } },
  );
  assert.equal(result.claimVerdict, 'inconclusive');
  assert.equal(result.configVerdict, 'inconclusive');
  assert.deepEqual(result.errored, ['l1-lint']);
});

test('judge は複数の層が止めた場合、主張の層が含まれていれば match とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-typecheck': 'fail', 'l1-lint': 'fail' } },
    { 'l1-typecheck': { code: 1, summary: '' }, 'l1-lint': { code: 1, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'match');
  assert.deepEqual(result.blockingLayers, ['L1']);
});
```

**`error(2)` が 1 つでもあれば両方の判定を `inconclusive` にし、緑赤の推論をしない。** 設計書 §6.1 の exit code 正規化と対応させる。ツールが実行できなかっただけの状態を「欠陥を検出した」と読み違えないためである。

- [ ] **Step 2: テストが失敗することを確認**

```bash
node --test verification/lib/judge.test.mjs
```

Expected: FAIL。`Cannot find module '.../judge.mjs'` になる。

- [ ] **Step 3: `judge.mjs` を実装**

```js
import { readFileSync } from 'node:fs';

const CODE_PASS = 0;
const CODE_FAIL = 1;

/**
 * 限定形式の expect.yml を読む。
 *
 * 完全な YAML パーサではない。トップレベルは id / pitfall / claimed_layer /
 * expect / expect_detection のみ、expect 系の子はインデント 2 スペースの
 * `<ゲート名>: <値>` のみを受け付ける。
 */
export function parseExpect(path) {
  const parsed = { id: '', pitfall: '', claimedLayer: '', expect: {}, expectDetection: {} };
  let section = null;

  for (const rawLine of readFileSync(path, 'utf8').split('\n')) {
    if (rawLine.trim() === '' || rawLine.trim().startsWith('#')) {
      continue;
    }

    const nested = /^ {2}([\w-]+):\s*(\S+)\s*$/.exec(rawLine);
    if (nested !== null && section !== null) {
      const [, key, value] = nested;
      if (section === 'expect') {
        parsed.expect[key] = value;
      } else {
        parsed.expectDetection[key] = value === 'true';
      }
      continue;
    }

    const top = /^([\w_]+):\s*(.*)$/.exec(rawLine);
    if (top === null) {
      throw new Error(`expect.yml の解釈できない行です: ${rawLine}`);
    }
    const [, key, value] = top;
    if (key === 'expect' || key === 'expect_detection') {
      section = key === 'expect' ? 'expect' : 'expect_detection';
      continue;
    }
    section = null;
    if (key === 'id') parsed.id = value.trim();
    else if (key === 'pitfall') parsed.pitfall = value.trim();
    else if (key === 'claimed_layer') parsed.claimedLayer = value.trim();
    else throw new Error(`expect.yml の未知のキーです: ${key}`);
  }

  // 値の妥当性を検査する。構造が正しくても中身が不正だと判定が静かに壊れる:
  // claimed_layer が空や小文字だと blockingLayers に一致しえず claimVerdict が恒に
  // mismatch になり、expect が空だと mismatches が空になって configVerdict が恒に
  // match になる。どちらも「ハーネスが何も検証していないのに結果が出る」状態なので、
  // 黙って通さず throw する。throw すれば run-all.sh が「⚠️ 実行不能」行を出す。
  if (!/^L[1-5]$/.test(parsed.claimedLayer)) {
    throw new Error(`expect.yml の claimed_layer が不正です: ${parsed.claimedLayer}`);
  }
  if (Object.keys(parsed.expect).length === 0) {
    throw new Error('expect.yml の expect が空です');
  }
  for (const [gate, value] of Object.entries(parsed.expect)) {
    if (value !== 'pass' && value !== 'fail') {
      throw new Error(`expect.yml の expect.${gate} は pass か fail のみです: ${value}`);
    }
  }

  return parsed;
}

/** ゲート実行結果の TSV を読む */
export function parseActual(path) {
  const actual = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (line.trim() === '') continue;
    const [gate, code, ...rest] = line.split('\t');
    actual[gate] = { code: Number(code), summary: rest.join('\t') };
  }
  return actual;
}

/** ゲート名から層を導く（'l1-lint' → 'L1'） */
function layerOfGate(gate) {
  return gate.slice(0, 2).toUpperCase();
}

/**
 * 期待と実測を突き合わせ、独立した 2 つの判定を返す。
 *
 *   claimVerdict  手順書の主張（claimed_layer）どおりの層が止めたか。検証の本題。
 *   configVerdict expect の各ゲートの pass/fail が実測と一致するか。設定の回帰検出。
 *
 * error(2) が 1 つでもあれば両方 inconclusive とし、緑赤の推論をしない。
 * ツールが実行できなかっただけの状態を「欠陥を検出した」と読み違えないため。
 */
export function judge(expected, actual) {
  const errored = Object.entries(actual)
    .filter(([, r]) => r.code !== CODE_PASS && r.code !== CODE_FAIL)
    .map(([gate]) => gate);

  const blockedBy = Object.entries(actual)
    .filter(([, r]) => r.code === CODE_FAIL)
    .map(([gate]) => gate);

  const blockingLayers = [...new Set(blockedBy.map(layerOfGate))];

  if (errored.length > 0) {
    return {
      claimVerdict: 'inconclusive',
      configVerdict: 'inconclusive',
      errored,
      blockedBy,
      blockingLayers,
      mismatches: [],
    };
  }

  const mismatches = [];
  for (const [gate, want] of Object.entries(expected.expect)) {
    const result = actual[gate];
    if (result === undefined) {
      mismatches.push({ gate, expected: want, actual: 'not-run' });
      continue;
    }
    const got = result.code === CODE_FAIL ? 'fail' : 'pass';
    if (got !== want) {
      mismatches.push({ gate, expected: want, actual: got });
    }
  }

  let claimVerdict;
  if (blockedBy.length === 0) {
    claimVerdict = 'not-caught';
  } else if (blockingLayers.includes(expected.claimedLayer)) {
    claimVerdict = 'match';
  } else {
    claimVerdict = 'mismatch';
  }

  return {
    claimVerdict,
    configVerdict: mismatches.length === 0 ? 'match' : 'mismatch',
    errored,
    blockedBy,
    blockingLayers,
    mismatches,
  };
}

// CLI: node judge.mjs <expect.yml> <actual.tsv>
if (process.argv[1]?.endsWith('judge.mjs') === true) {
  const [, , expectPath, actualPath] = process.argv;
  if (expectPath === undefined || actualPath === undefined) {
    process.stderr.write('usage: node judge.mjs <expect.yml> <actual.tsv>\n');
    process.exit(2);
  }
  const expected = parseExpect(expectPath);
  const actual = parseActual(actualPath);
  process.stdout.write(`${JSON.stringify({ ...judge(expected, actual), expected })}\n`);
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
node --test verification/lib/judge.test.mjs
```

Expected: PASS。9 件すべて成功。

- [ ] **Step 5: `judge.mjs` を lint 対象に入れる**

Task 1 Step 5 でルート設定の `ignores` に `verification/lib/**` を入れていた。実装ができたので外し、型情報無しの lint 対象にする。

ルート `eslint.config.mjs` を次に置き換える。

```js
import base from '@repo/eslint-config';

export default [
  ...base,
  {
    // docs は Markdown だけなので lint 対象外。
    // apps/** は絶対に入れないこと。files を伴わない ignores はグローバル ignore で
    // ディレクトリ走査そのものを止めるため、apps 配下が L1 ゲートの対象外になる。
    // apps/* は自分の eslint.config.mjs を持つが、それは「ルートで無視してよい」
    // という意味ではない。ルートの eslint . が全体を走査する。
    ignores: ['docs/**'],
  },
];
```

`verification/lib/*.mjs` はベース設定の `files: ['**/*.js', '**/*.mjs', '**/*.cjs']` ブロックで `disableTypeChecked` が当たるので、型情報付きルール抜きで lint される。

- [ ] **Step 6: lint が通ることを確認**

```bash
pnpm exec eslint . --max-warnings=0; echo "EXIT=$?"
```

Expected: `EXIT=0`。違反が出た場合は `judge.mjs` / `judge.test.mjs` を直す（`no-console` は使っていないが、`process.stdout.write` は対象外なので問題ない）。

- [ ] **Step 7: `verification/run-case.sh` を作成**

```bash
#!/usr/bin/env bash
# 1 つの検証ケースを実行する。
#
#   verification/run-case.sh <CASE-ID>
#
# 手順:
#   1. 作業ツリーがクリーンか確認（汚れていたら中断）
#   2. 検証ブランチの残存を確認（あれば中断）
#   3. 現在のブランチから verify/<CASE-ID> ブランチを切る
#   4. case.patch を適用してコミット
#   5. l2-install.sh を先に実行。失敗したら後続を打ち切る
#   6. 残りのゲートを実行し、結果を /tmp に記録
#   7. 元のブランチに戻り検証ブランチを削除。戻れなかったら中断する
#   8. judge.mjs で期待と突き合わせ、TSV 1 行を標準出力へ
#
# 結果を /tmp に書いてから元のブランチに戻るのが要点。検証ブランチ上で
# RESULTS.md を書くとブランチ削除で消える。
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

CASE_ID="${1:-}"
if [ -z "$CASE_ID" ]; then
  printf 'usage: %s <CASE-ID>\n' "$0" >&2
  exit 2
fi

# 作業ツリーの確認は引数の妥当性より先。このスクリプトはブランチを切って
# パッチを当てるので、汚れたツリーでは何もしてはいけない。ケース ID が
# 間違っていても、まず「今この状態では動かせない」を報告する。
if [ -n "$(git status --porcelain)" ]; then
  printf 'エラー: 作業ツリーが汚れています。コミットまたは stash してください\n' >&2
  git status --short >&2
  exit 2
fi

CASE_DIR="verification/cases/$CASE_ID"
if [ ! -f "$CASE_DIR/case.patch" ] || [ ! -f "$CASE_DIR/expect.yml" ]; then
  printf 'エラー: %s に case.patch と expect.yml が必要です\n' "$CASE_DIR" >&2
  exit 2
fi

BRANCH="verify/$CASE_ID"
if git show-ref --quiet "refs/heads/$BRANCH"; then
  printf 'エラー: ブランチ %s が残っています。前回が異常終了しています\n' "$BRANCH" >&2
  printf '  復旧: git branch -D %s\n' "$BRANCH" >&2
  exit 2
fi

BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
WORK=$(mktemp -d)
ACTUAL="$WORK/actual.tsv"
LOGS="$WORK/logs"
mkdir -p "$LOGS"

cleanup() {
  git checkout --quiet "$BASE_BRANCH" 2>/dev/null || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
}
trap cleanup EXIT

git checkout --quiet -b "$BRANCH"

if ! git apply --index "$CASE_DIR/case.patch" 2>"$LOGS/apply.log"; then
  printf 'エラー: パッチが適用できません。case.patch の更新が必要です\n' >&2
  cat "$LOGS/apply.log" >&2
  exit 2
fi
if ! git commit --quiet -m "verify: $CASE_ID"; then
  printf 'エラー: 検証コミットに失敗しました\n' >&2
  exit 2
fi

# ゲートを実行する。l2-install は必ず先。依存が無ければ他が動かないため、
# また install 失敗による連鎖失敗を「ゲートが欠陥を検出した」と誤記録しないため。
run_gate() {
  local gate="$1"
  local log="$LOGS/$gate.log"
  "./scripts/gates/$gate.sh" >"$log" 2>&1
  local code=$?
  local summary
  summary=$(tail -n 1 "$log" | tr -d '\t' | cut -c1-120)
  printf '%s\t%s\t%s\n' "$gate" "$code" "$summary" >>"$ACTUAL"
  return "$code"
}

if ! run_gate l2-install; then
  printf 'l2-install が pass しなかったため後続ゲートを打ち切りました\n' >&2
else
  run_gate l1-typecheck || true
  run_gate l1-lint || true
fi

cleanup

# cleanup が本当に成功したかを検査する。cleanup 内の git は両方 || true で
# 握り潰しているため、失敗しても何も起きない。ゲートが追跡ファイルを汚すと
# checkout が失敗し、続く branch -D も「チェックアウト中のブランチは消せない」
# ため必ず失敗する。それを見逃すと、欠陥パッチ適用済みの検証ブランチ上で
# judge が走り、正常な JSON を出して exit 0 してしまう。
if [ "$(git rev-parse --abbrev-ref HEAD)" != "$BASE_BRANCH" ] \
  || git show-ref --quiet "refs/heads/$BRANCH"; then
  printf 'エラー: %s への復帰に失敗しました。手動で復旧してください\n' "$BASE_BRANCH" >&2
  printf '  復旧: git checkout -f %s && git branch -D %s\n' "$BASE_BRANCH" "$BRANCH" >&2
  git status --short >&2
  exit 2
fi
trap - EXIT

node verification/lib/judge.mjs "$CASE_DIR/expect.yml" "$ACTUAL"
```

- [ ] **Step 8: `verification/run-all.sh` を作成**

```bash
#!/usr/bin/env bash
# 全検証ケースを実行し verification/RESULTS.md を生成する。
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

RESULTS=verification/RESULTS.md
WORK=$(mktemp -d)

{
  printf '# 検証結果マトリクス\n\n'
  printf '`verification/run-all.sh` が生成する。手で編集しない。\n\n'
  printf '「手順書の主張」と「実際に止めた層」を並べるのがこの表の眼目である。\n'
  printf '一致すれば手順書が正しく、ズレれば手順書への修正提案になる。\n\n'
  printf '| ケース | 落とし穴 | 手順書の主張 | 実際に止めた層 | 判定 |\n'
  printf '|---|---|---|---|---|\n'
} >"$WORK/head.md"

for case_dir in verification/cases/*/; do
  case_id=$(basename "$case_dir")
  printf '=== %s ===\n' "$case_id" >&2
  if ! ./verification/run-case.sh "$case_id" >"$WORK/$case_id.json"; then
    printf '| %s | (実行失敗) | | | ⚠️ 実行不能 |\n' "$case_id" >>"$WORK/rows.md"
    continue
  fi
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const mark = {
      match: "✅ 一致",
      mismatch: "❌ 別の層が止めた",
      "not-caught": "❌ どの層も止めなかった",
      inconclusive: "⚠️ 判定不能",
    }[r.claimVerdict];
    const blocked = r.blockedBy.length > 0 ? r.blockedBy.join(", ") : "（なし）";
    // 設定の回帰（expect と実測のずれ）は本題ではないので注記として添える
    const note = r.configVerdict === "mismatch"
      ? " ※設定ずれ: " + r.mismatches.map(m => `${m.gate} 期待 ${m.expected} → 実測 ${m.actual}`).join(" / ")
      : "";
    process.stdout.write(`| ${r.expected.id} | ${r.expected.pitfall} | ${r.expected.claimedLayer} | ${blocked} | ${mark}${note} |\n`);
  ' "$WORK/$case_id.json" >>"$WORK/rows.md"
done

cat "$WORK/head.md" "$WORK/rows.md" >"$RESULTS"
printf '\n生成しました: %s\n' "$RESULTS" >&2
cat "$RESULTS"
```

- [ ] **Step 9: 実行権限を付け、ケースが無い状態で動くことを確認**

```bash
chmod +x verification/run-case.sh verification/run-all.sh
./verification/run-case.sh 2>&1 | head -3; echo "EXIT=${PIPESTATUS[0]}"
```

Expected: `usage: ./verification/run-case.sh <CASE-ID>` が出て `EXIT=2`。

```bash
./verification/run-case.sh L1-99-nonexistent 2>&1 | head -3; echo "EXIT=${PIPESTATUS[0]}"
```

Expected: `エラー: verification/cases/L1-99-nonexistent に case.patch と expect.yml が必要です` が出て `EXIT=2`。

- [ ] **Step 10: 作業ツリーが汚れているときに中断することを確認**

```bash
printf '# 一時的な変更\n' >> README.md
./verification/run-case.sh L1-99-nonexistent 2>&1 | head -2
git checkout README.md
```

Expected: `エラー: 作業ツリーが汚れています` が出る（ケース不存在のチェックより先に出る）。

- [ ] **Step 11: lint とテストが通ることを確認**

```bash
pnpm exec eslint . --max-warnings=0; echo "LINT=$?"
node --test verification/lib/judge.test.mjs 2>&1 | tail -3
./scripts/gates/gates.test.sh | tail -2
```

Expected: `LINT=0`、judge のテスト 12 件成功、ゲートのテスト 6 件成功。

- [ ] **Step 12: コミット**

```bash
git add verification eslint.config.mjs
git commit -m "feat: 検証ハーネス（run-case / run-all / judge）を追加"
```

---

## Task 5: L1 検証ケース 3 本でハーネスの判定を実証

**Files:**
- Create: `verification/cases/L1-02-explicit-any/{case.patch, expect.yml}`
- Create: `verification/cases/L1-05-unchecked-index/{case.patch, expect.yml}`
- Create: `verification/cases/L1-01-eslint-disable-abuse/{case.patch, expect.yml}`

**Interfaces:**
- Consumes: `verification/run-case.sh`（Task 4）、`expect.yml` の限定形式（Task 4）、ゲートの exit code 契約（Task 3）
- Produces: 3 ケースが `run-case.sh` で `claimVerdict: "match"` を返す状態

この 3 本を先に作るのは、**ハーネスが「lint で止まる」「typecheck で止まる」の 2 系統を正しく判定できることを実証する**ためである。`L1-02` と `L1-01` は lint 系、`L1-05` は typecheck 系。

### パッチの作り方

`case.patch` は手で書かず、実際に編集して `git diff` で出力する。

```bash
mkdir -p verification/cases/<CASE-ID>
# ... ファイルを編集 ...
git diff > verification/cases/<CASE-ID>/case.patch
git checkout -- .
```

**一時ブランチは作らない。** パッチ作成はコミットを伴わないので、追跡ファイルを編集して
`git diff` を取り、`git checkout -- .` で戻すだけで足りる。`verification/cases/` は未追跡
なので `git diff` には現れない。ブランチを切ると、戻り先を間違えたときに気づきにくい。

**パッチは context 付き（既定の 3 行）で作る。** 周辺コードが変わったときに黙って別の場所に当たるのではなく、失敗して気づけるようにするため。設計書 §8.3 の「パッチが当たらない → 即中断」はこの前提に立っている。

**ケースを作ったら実行前にコミットする。** `run-case.sh` は作業ツリーがクリーンでなければ exit 2 で中断する。`git status --porcelain` は未追跡ファイルも `??` として報告するので、`verification/cases/<ID>/` を作っただけの状態では実行できない。ケースをまとめて作り、コミットしてから実行する。

- [ ] **Step 1: `L1-02-explicit-any` のパッチを作る**

`apps/web/src/api/client.ts` の `fetchOrders` の戻り値のキャストを `any` 経由にする。

編集内容（`as OrderView[]` を `as any` に変える）:

```ts
  return (await response.json()) as any;
```

```bash
mkdir -p verification/cases/L1-02-explicit-any
# 上記の編集を apps/web/src/api/client.ts に加える
git diff > verification/cases/L1-02-explicit-any/case.patch
git checkout -- .
```

パッチの中身を目で確認し、`-  return (await response.json()) as OrderView[];` と `+  return (await response.json()) as any;` の 2 行だけが変更になっていることを確かめる。

- [ ] **Step 2: `L1-02-explicit-any` の `expect.yml` を作る**

```yaml
id: L1-02-explicit-any
pitfall: any で型チェックを回避する
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: fail
```

`l1-typecheck: pass` としているのは、`as any` は型エラーにならないためである。**`any` を止めるのは lint だけ**という切り分けが、この ケースの検証内容である。

- [ ] **Step 3: ケースを実行して判定が一致することを確認**

```bash
./verification/run-case.sh L1-02-explicit-any
```

Expected: JSON が出力され、`"claimVerdict":"match"` と `"blockedBy":["l1-lint"]` を含む。

`"claimVerdict":"mismatch"` になった場合、`mismatches` の内容を読んで原因を切り分ける。`l1-typecheck` が fail していたら `as any` が型エラーを起こしているので、パッチの当て方を見直す。`l1-lint` が pass していたら `no-explicit-any` が効いていないので Task 2 の設定を見直す。

- [ ] **Step 4: 実行後に作業ツリーとブランチが元に戻っていることを確認**

```bash
git status --porcelain; echo "(空なら OK)"
git branch --list 'verify/*'; echo "(空なら OK)"
git rev-parse --abbrev-ref HEAD
```

Expected: `git status` が空、`verify/*` ブランチが無い、HEAD が元のブランチ。

- [ ] **Step 5: `L1-05-unchecked-index` のパッチを作る**

`noUncheckedIndexedAccess` が効くことを検証する。`apps/web/src/features/orders/orderTotal.ts` に、配列の添字アクセスの `undefined` を考慮しない関数を足す。

```ts
/** 先頭の注文の商品名を返す */
export function firstProductName(orders: readonly OrderView[]): string {
  return orders[0].productName;
}
```

`noUncheckedIndexedAccess: true` により `orders[0]` は `OrderView | undefined` なので、`.productName` へのアクセスが型エラーになる。

```bash
mkdir -p verification/cases/L1-05-unchecked-index
# 上記の関数を apps/web/src/features/orders/orderTotal.ts の末尾に追加
git diff > verification/cases/L1-05-unchecked-index/case.patch
git checkout -- .
```

- [ ] **Step 6: `L1-05-unchecked-index` の `expect.yml` を作る**

```yaml
id: L1-05-unchecked-index
pitfall: 配列添字アクセスの undefined を考慮しない
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: fail
  l1-lint: fail
```

**`l1-lint: fail` にしているのは、型情報付きルールが有効なため lint 側も型エラーを拾う可能性があるからである。** 実行してどちらが止めたかを確認し、実測とずれていたら `expect` の値を実測に合わせて更新する。

**`expect` を実測に合わせるのは正当だが、`claimed_layer` を実測に合わせてはいけない。** `expect`（各ゲートの pass/fail）は「自分のゲートがどう振る舞うか」のスナップショットであり、初回実行で確定させるのが正しい使い方である。一方 `claimed_layer` は手順書 §10 の主張そのもので、これが検証対象である。ここを書き換えると `claimVerdict` が恒真になり、ハーネスが何も検証しなくなる。

- [ ] **Step 7: ケースを実行して判定を確認**

```bash
./verification/run-case.sh L1-05-unchecked-index
```

Expected: `"claimVerdict":"match"`。`configVerdict` が `mismatch` なら `expect` を実測に合わせて更新し、再実行する。`claimVerdict` が `mismatch` / `not-caught` の場合は **`claimed_layer` を変えてはいけない** — それは手順書の主張であり検証対象である。その結果をそのまま `RESULTS.md` に残す。

- [ ] **Step 8: `L1-01-eslint-disable-abuse` のパッチを作る**

ファイル全体を黙らせる `/* eslint-disable */` を入れる。`no-unlimited-disable` が捕まえる。

`apps/api/src/orders/orders.service.ts` の先頭に 1 行入れる。

```ts
/* eslint-disable */
```

```bash
mkdir -p verification/cases/L1-01-eslint-disable-abuse
# 上記の 1 行を apps/api/src/orders/orders.service.ts の先頭に追加
git diff > verification/cases/L1-01-eslint-disable-abuse/case.patch
git checkout -- .
```

- [ ] **Step 9: `L1-01-eslint-disable-abuse` の `expect.yml` を作る**

```yaml
id: L1-01-eslint-disable-abuse
pitfall: eslint-disable でファイル全体を黙らせる
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: fail
```

- [ ] **Step 10: ケースを実行して判定を確認**

```bash
./verification/run-case.sh L1-01-eslint-disable-abuse
```

Expected: `"claimVerdict":"match"`、`"blockedBy":["l1-lint"]`。

`l1-lint` が pass した場合は `no-unlimited-disable` が効いていない。`/* eslint-disable */` がファイル先頭にあると ESLint 自身のルールも無効化されるため、`no-unlimited-disable` が自分を無効化されてしまう可能性がある。その場合は**それ自体が重要な発見**なので、パッチを変えずに報告する（手順書 §2.4 の抑制コメント対策が自己無効化に対して無力であることを意味する）。

- [ ] **Step 11: 3 ケースを続けて実行しても状態が汚れないことを確認**

```bash
for c in L1-01-eslint-disable-abuse L1-02-explicit-any L1-05-unchecked-index; do
  ./verification/run-case.sh "$c" | node -e 'const r=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(r.expected.id, r.claimVerdict, r.configVerdict, r.blockedBy.join(","))'
done
git status --porcelain; echo "(空なら OK)"
git branch --list 'verify/*'; echo "(空なら OK)"
```

Expected: 3 行とも `claimVerdict` と `configVerdict` の両方が `match` で、作業ツリーとブランチが元に戻っている。

- [ ] **Step 12: コミット**

```bash
git add verification/cases
git commit -m "feat: L1 検証ケース 3 本（any / 添字アクセス / eslint-disable 乱用）を追加"
```

---

## Task 6: 残り 3 ケースと全件実行

**Files:**
- Create: `verification/cases/L1-03-floating-promise/{case.patch, expect.yml}`
- Create: `verification/cases/L1-04-unused-disable/{case.patch, expect.yml}`
- Create: `verification/cases/L1-06-web-imports-api/{case.patch, expect.yml}`
- Create: `verification/RESULTS.md`（`run-all.sh` が生成）
- Modify: `docs/superpowers/phase0-findings.md`（Phase 1 の結論を追記）

**Interfaces:**
- Consumes: `verification/run-all.sh`（Task 4）、Task 5 の 3 ケース
- Produces: `verification/RESULTS.md` に L1 系 6 ケース全件の判定が入った状態

- [ ] **Step 1: `L1-03-floating-promise` のパッチを作る**

`await` 忘れを入れる。`apps/api/src/orders/orders.service.ts` の `findByUser` で `await` を落とす。

```ts
  async findByUser(userId: string): Promise<OrderResponseDto[]> {
    const orders = this.prisma.order.findMany({
```

`await` を消すと `orders` が Promise になり、`orders.map` が型エラーになる。**つまり typecheck でも止まる。** それを含めて記録する。

```bash
mkdir -p verification/cases/L1-03-floating-promise
# apps/api/src/orders/orders.service.ts の findByUser から await を削除
git diff > verification/cases/L1-03-floating-promise/case.patch
git checkout -- .
```

- [ ] **Step 2: `L1-03-floating-promise` の `expect.yml` を作る**

```yaml
id: L1-03-floating-promise
pitfall: await 忘れで Promise を放置する
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: fail
  l1-lint: fail
```

- [ ] **Step 3: ケースを実行して判定を確認**

```bash
./verification/run-case.sh L1-03-floating-promise
```

Expected: `"claimVerdict":"match"`。`configVerdict` が `mismatch` なら `expect` を実測に合わせて更新し、理由をコミットメッセージに書く。`claimVerdict` の `mismatch` / `not-caught` は手順書とのズレそのものなので、**修正せず結果として記録する**。

- [ ] **Step 4: `L1-04-unused-disable` のパッチを作る**

効いていない抑制コメントを残す。`linterOptions.reportUnusedDisableDirectives: 'error'` が捕まえる。

`apps/api/src/discount/discount.ts` の `applyDiscount` の直前に、実際には違反していないルールの抑制を書く。

```ts
// eslint-disable-next-line eqeqeq -- 実際には == を使っていないので効かない
export function applyDiscount(price: number, isMember: boolean): number {
```

`require-description` が有効なので `--` 以降の理由は必須である。理由を書いた上で「効いていない」ことを検出できるかが、このケースの検証内容である。

```bash
mkdir -p verification/cases/L1-04-unused-disable
# 上記のコメントを apps/api/src/discount/discount.ts に追加
git diff > verification/cases/L1-04-unused-disable/case.patch
git checkout -- .
```

- [ ] **Step 5: `L1-04-unused-disable` の `expect.yml` を作る**

```yaml
id: L1-04-unused-disable
pitfall: 効いていない eslint-disable を残す
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: fail
```

- [ ] **Step 6: ケースを実行して判定を確認**

```bash
./verification/run-case.sh L1-04-unused-disable
```

Expected: `"claimVerdict":"match"`、`"blockedBy":["l1-lint"]`。

これは Global Constraints で述べた仮説 7 の実地確認でもある。**`no-unused-disable` を入れていない構成でも `linterOptions` だけで検出できる**ことを、このケースが示す。

- [ ] **Step 7: `L1-06-web-imports-api` のパッチを作る**

Web から API の内部実装を直接 import する。`no-restricted-imports` が捕まえる。

`apps/web/src/features/orders/orderTotal.ts` に import を足し、実際に使う関数を 1 つ追加する。import しただけで未使用だと `no-unused-vars` で止まってしまい、`no-restricted-imports` が効いたのか区別できなくなるため、必ず使う。

追加する内容（ファイル末尾）:

```ts
import { applyDiscount } from '../../../../api/src/discount/discount';

/** API の内部実装を直接使って割引を再計算する（禁止された依存） */
export function recomputeDiscount(order: OrderView): number {
  return applyDiscount(order.unitPrice * order.quantity, true);
}
```

`import` 文はファイル先頭にまとめる必要があるため、既存の `import type { OrderView } ...` の直後に置く。

```bash
mkdir -p verification/cases/L1-06-web-imports-api
# 上記の import を既存 import の直後に、recomputeDiscount をファイル末尾に追加する
git diff > verification/cases/L1-06-web-imports-api/case.patch
git checkout -- .
```

**このケースは typecheck も落ちる可能性が高い。** `apps/web/tsconfig.json` の `include` は `src/**` と `e2e/**` だけなので、`apps/api/src` のファイルは web のプロジェクトに含まれず解決できない。実行して確認し、実測に合わせて `expect.yml` を書く。

- [ ] **Step 8: `L1-06-web-imports-api` の `expect.yml` を作る**

まず次で作り、実行結果に合わせて修正する。

```yaml
id: L1-06-web-imports-api
pitfall: Web から API の内部実装を直接 import する
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: fail
  l1-lint: fail
```

- [ ] **Step 9: ケースを実行して判定を確認**

```bash
./verification/run-case.sh L1-06-web-imports-api
```

Expected: `"claimVerdict":"match"`。`configVerdict` が `mismatch` なら `expect` を実測に合わせて更新する。`claimVerdict` の `mismatch` / `not-caught` は修正せず結果として記録する。

- [ ] **Step 10: 全件実行して `RESULTS.md` を生成**

```bash
./verification/run-all.sh
```

Expected: 6 ケースすべてが `✅ 一致` で `verification/RESULTS.md` に並ぶ。`⚠️ 判定不能` が出た場合は該当ゲートが exit 2 を返しているので、原因（pnpm が無い、リポジトリルート外など）を調べる。

- [ ] **Step 11: 実行後の状態を確認**

```bash
git status --porcelain
git branch --list 'verify/*'; echo "(空なら OK)"
pnpm turbo build typecheck test 2>&1 | grep -E 'Tests|Tasks:'
pnpm exec eslint . --max-warnings=0; echo "LINT=$?"
```

Expected: `RESULTS.md` だけが未コミットの変更として出る。`verify/*` ブランチは無い。9 タスク成功・23 テスト・`LINT=0`。

- [ ] **Step 12: `docs/superpowers/phase0-findings.md` に Phase 1 の結論を追記**

`## 1. 手順書への修正提案候補` の末尾に次の 2 節を足す。

```markdown
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
```

- [ ] **Step 13: `RESULTS.md` とドキュメントをコミット**

```bash
git add verification docs/superpowers/phase0-findings.md
git commit -m "feat: L1 検証ケース 6 本を揃え RESULTS.md を生成"
```

---

## Phase 1 完了条件

設計書 §10 の Phase 1 完了条件に対応する。

- [ ] `pnpm exec eslint . --max-warnings=0` が exit 0（L1 lint が緑）
- [ ] `pnpm turbo typecheck` が成功（L1 typecheck が緑）
- [ ] `pnpm turbo build typecheck test` が 9 タスク・23 テスト成功（既存機能を壊していない）
- [ ] `./scripts/gates/gates.test.sh` が 6 件成功（exit code 契約が守られている）
- [ ] `node --test verification/lib/judge.test.mjs` が 12 件成功（判定ロジックが正しい）
- [ ] `verification/RESULTS.md` に L1 系 6 ケースの判定が入っている
- [ ] `./verification/run-all.sh` の実行後、作業ツリーがクリーンで `verify/*` ブランチが残っていない
- [ ] 仮説 6・7 に結論が出て `docs/superpowers/phase0-findings.md` に記録されている

## Phase 2 への申し送り

| # | 内容 | Phase 2 での対応 |
|---|---|---|
| 1 | `scripts/gates/l2-install.sh` は Phase 1 で作成済み | Semgrep・OSV-Scanner・gitleaks・新規依存検出のスクリプトを足す |
| 2 | `expect.yml` の `expect_detection` は読み取りのみ実装、判定は未実装 | `l2-new-deps` が非ブロックゲートなので、ここで判定を実装する |
| 3 | `verification/run-case.sh` はゲート一覧をハードコードしている | L2 のゲートを足す際、一覧の持ち方（配列 or ディレクトリ走査）を見直す |
| 4 | `--ignore-scripts` 付き install で Prisma Client が壊れないことを `l2-install.sh` で担保している | 仮説 2 の検証として、`prisma generate` の行を外すと何が起きるかを 1 回確認して記録する |
| 5 | ルート `eslint.config.mjs` の ignores は `docs/**` のみ | `apps/**` を足してはいけない（グローバル ignore が走査を止めゲートが空振りする）。`.semgrep/` の YAML は ESLint の対象外なので影響なし |
| 6 | `apps/web` の `OrderList.tsx` に `react-hooks/set-state-in-effect` の抑制コメントがある | 手順書 §2.4 は `exhaustive-deps` にしか言及しないが、`recommended-latest` はより広いルール面を持ち込む。Phase 6 レポート項目として記録済み |

## Phase 5 への申し送り

| # | 内容 | Phase 5 での対応 |
|---|---|---|
| 1 | 設計書 §8.2 の手順 9「`l5-ai-review` の出力を `verification/reviews/<CASE-ID>.md` に保存」は Phase 1 では未実装 | L5 ゲートを足す際に `run-case.sh` へ追加する。`.gitignore` の扱い（レビュー出力をコミットするか）も決める |
| 2 | `judge.mjs` の `expectDetection` は読み取りのみで判定していない | `l5-ai-review` は自動判定しない方針（設計書 §8.1）なので、`judge.mjs` は触らず目視判定の結果を手で `RESULTS.md` に追記する運用にする |
