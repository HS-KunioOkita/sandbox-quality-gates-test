# Phase 4（L4: ミューテーションテスト）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手順書 §5（L4 = Stryker ミューテーションテスト）を api / web の両方に導入し、`l4-mutation` をブロッキングゲートとして `GATE_ORDER` に加え、L4 系 2 ケースの判定を出して仮説 4 に結論を与える。

**Architecture:** Stryker を `apps/api`（jest-runner）と `apps/web`（vitest-runner）に入れる。まず `break: null` でフル実行してスコアを実測し、その実測値から閾値を決める（手順書 §5.5 の順序）。ブロッキングゲート `scripts/gates/l4-mutation.sh` は手順書 §5.3 の差分限定スクリプト `scripts/stryker-diff.sh` を薄く包み、exit code を 0/1/2 の 3 値へ正規化する。web 側は手順書 §5.3 が `apps/api` しか見ないため、ゲートには入らず nightly 相当のフル実行でのみ測る。

**Tech Stack:** `@stryker-mutator/core@9.6.1`、`@stryker-mutator/jest-runner@9.6.1`（api）、`@stryker-mutator/vitest-runner@9.6.1`（web）、Jest 30 + ts-jest 29.4、Vitest 4.1.10、bash 3.2、Node v24.11.1、pnpm 11.1.1。

## Global Constraints

このリポジトリ固有の規律。**全タスクの受け入れ条件に暗黙に含まれる。**

- **`expect.yml` の `claimed_layer` は絶対に変えてはいけない。** 手順書 §10 の主張そのものであり、これが検証対象である。`expect`（各ゲートの pass/fail）は実測に合わせて更新してよい。
- **判定を `match` にするために `case.patch` を書き換えてはいけない。** `mismatch` / `not-caught` が出たなら、それがこのプロジェクトの成果物である。
- ゲートの exit code は `0`=pass / `1`=fail（欠陥を検出）/ `2`=error（ツールが実行できなかった）。**error を fail と誤記録しないことが最重要**（設計書 §6.1）。
- 依存は完全固定する（`^` / `~` を付けない）。`pnpm add` が `^` を付けたら手で外す。
- **`corepack enable` を実行しない。** pnpm 11.1.1 はグローバルインストール済み。
- **`pnpm-workspace.yaml` の `minimumReleaseAge` / `minimumReleaseAgeExclude` / `overrides` を自分の判断で編集しない。** 依存追加が拒否されたら、または `l2-osv` が新しい脆弱性で赤くなったら、**状況を報告して人間の判断を仰いで停止する**（本フェーズの決定 3、findings §4 の運用ルール）。
- ケースを作ったら**コミットしてから** `run-case.sh` を実行する（`git status --porcelain` は未追跡ファイルも報告し、汚れたツリーでは exit 2 で止まる）。
- **`run-all.sh` は必ずバックグラウンドで実行する。** Bash ツールのタイムアウト上限（10 分）を超える実行を実測している。
- `run-all.sh` は追跡ファイルの `RESULTS.md` を書き換える。実行後にコミットするか `git checkout` で戻す。
- **壁時計の絶対値を根拠に判断しない。** 同一条件で 2.3 倍の幅が出る（§1.38）。数値を引くときはスコープと実行を明示する。
- **ゲートや設定を足したら、意図的に違反を 1 つ入れて赤くなることを確認する。** 赤確認は「実際に起こりうる壊し方」で行う（§1.13 / §1.44）。
- Docker Desktop の起動が必須（`l2-*` の 3 本と `l3-test`）。**`l4-mutation` は Docker を必要としない**（Jest の unit プロジェクトだけを回すため）。
- `shellcheck` 0.11.0 で `scripts/gates/*.sh` `scripts/stryker-diff.sh` `verification/*.sh` を検査し、指摘 0 を保つ。
- bash は **3.2**（macOS 標準）。連想配列（`declare -A`）や `${var,,}` は使えない。

## ブレインストーミングで確定した決定

| # | 決定 |
|---|---|
| 1 | **api + web の両方に Stryker を入れる**（手順書 §5.1 どおり）。web 側が動かなければ、それを findings に記録して api だけで進む（api をブロックしない） |
| 2 | **手順書 §5.3 の差分限定スクリプトと §5.5 の閾値手順をそのまま実装し、結果をそのまま残す。** ケースが ❌ になっても直さない。対照として `--force` 相当のフル実行も測り、差を数値で示す |
| 3 | **依存追加が pnpm / OSV に阻まれたら、その都度人間の判断を仰ぐ**（自分で除外リストを編集しない） |
| 4 | **`run-all.sh` の高速化は本フェーズではやらない**（Phase 5 で判断） |

## 手順書からの逸脱（3 点。すべてコメントと findings に理由を書く）

| 逸脱 | 理由 |
|---|---|
| **web は `GATE_ORDER` に入れず、nightly 相当のフル実行でのみ測る** | 手順書 §5.1/§5.2 は web にも Stryker を入れさせるが、**§5.3 の PR スクリプトは `apps/api` しかミューテートしない**。この非対称は手順書側の記述であり、そのまま再現して記録する |
| **`incremental` をハーネス内では切る（`false`）** | ハーネスは一時ブランチを毎回作って捨てる。前回結果の再利用がケース間の判定を汚染しうる。手順書 §5.4 は incremental を推奨しているので、逸脱として記録する |
| **Stryker が回す Jest 設定を `unit` プロジェクトだけに絞る** | `integration` / `e2e` は `test/setup-db.ts` で Testcontainers の PostgreSQL を起動する。絞らないと mutant の数だけコンテナが起動する（申し送り #28） |

## ファイル構成

| ファイル | 責務 | タスク |
|---|---|---|
| `apps/api/jest.config.ts` | 変更。`unit` プロジェクトの定義を named export に切り出す（Stryker 用設定との単一情報源） | 1 |
| `apps/api/jest.stryker.config.ts` | 新規。`unit` プロジェクトだけを持つ Jest 設定。Stryker がこれを使う | 1 |
| `apps/api/stryker.config.json` | 新規。手順書 §5.2 準拠 + 逸脱 3 点 | 1 |
| `apps/api/tsconfig.json` | 変更。`include` に `jest.stryker.config.ts` を追加（§1.37 の再発防止） | 1 |
| `apps/web/stryker.config.json` | 新規。手順書 §5.2 準拠（web 側） | 2 |
| `scripts/stryker-diff.sh` | 新規。手順書 §5.3 の差分限定実行。仮説 4 の検証対象そのもの | 3 |
| `scripts/gates/l4-mutation.sh` | 新規。上を包んで exit code を 3 値へ正規化するブロッキングゲート | 4 |
| `scripts/gates/gates.list.sh` | 変更。`GATE_ORDER` の末尾に `l4-mutation` を足す（1 箇所のみ。申し送り #30） | 4 |
| `verification/run-case.sh` | 変更。`l3-test` が pass でないケースでは `l4-mutation` を実行しない | 5 |
| `verification/cases/*/expect.yml` | 変更。既存ケースに `l4-mutation` の実測値を書く | 5 |
| `verification/cases/L4-01-empty-assertion/` | 新規。`case.patch` + `expect.yml` | 6 |
| `verification/cases/L4-02-off-by-one-fixed-by-test/` | 新規。`case.patch` + `expect.yml` | 6 |
| `verification/RESULTS.md` | 生成物。16 ケース分に更新 | 7 |
| `docs/superpowers/phase0-findings.md` | 変更。§1.45 以降に発見を追記、§3 の Phase 4 表を完了済みに更新、§4 に受け入れ確認記録を追加 | 7 |
| `CLAUDE.md` | 変更。「現在地」をゲート 9 本 / 16 ケースに更新 | 7 |

---

## Task 1: api に Stryker を入れ、`break: null` でフル実行スコアを実測する

**Files:**
- Modify: `apps/api/package.json`（devDependencies）
- Modify: `pnpm-lock.yaml`
- Modify: `apps/api/jest.config.ts:19-45`（`unit` プロジェクトを named export に切り出す）
- Create: `apps/api/jest.stryker.config.ts`
- Create: `apps/api/stryker.config.json`
- Modify: `apps/api/tsconfig.json`（`include`）

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces: `apps/api/jest.config.ts` から `export const unitProject`（Jest の `unit` プロジェクト定義）。`apps/api/stryker.config.json`（`testRunner: "jest"` / `jest.configFile: "jest.stryker.config.ts"` / `thresholds.break: null`）。api のフル実行ミューテーションスコア（Task 4 が閾値を決めるのに使う数値）

- [ ] **Step 1: 依存を追加する**

```bash
pnpm --filter api add -D @stryker-mutator/core@9.6.1 @stryker-mutator/jest-runner@9.6.1
```

期待: 成功し、`apps/api/package.json` の `devDependencies` に `"@stryker-mutator/core": "9.6.1"` と `"@stryker-mutator/jest-runner": "9.6.1"` が**キャレット無しで**入る。`^` が付いていたら手で外して `pnpm install --lockfile-only` で lockfile を追従させる。

**失敗したら止まる。** 特に `ERR_PNPM_NO_MATURE_MATCHING_VERSION`（`minimumReleaseAge: 10080` による拒否）が出た場合、`pnpm-workspace.yaml` を編集してはいけない。エラー全文と、拒否の原因になったパッケージ名を報告して人間の判断を仰ぐ（Global Constraints）。`@stryker-mutator/core@9.6.1` 自体は 2026-04-10 公開なので 7 日ルールは単体では満たす。発火するとしたら無関係な既存依存が原因である（§1.21 と同じ形）。

- [ ] **Step 2: `unit` プロジェクトの定義を named export に切り出す**

`apps/api/jest.config.ts` の `projects` 配列の 1 つ目（`displayName: 'unit'`）を、配列の外の `const` に移して export する。**同じ定義を Stryker 用設定に写すと、片方だけ直して「Stryker が古い設定で回る」事故になる**ため、単一情報源にする。

```ts
// Stryker からも参照する（jest.stryker.config.ts）。Stryker は mutant 1 つごとに
// テストを回すので、Testcontainers を使う integration / e2e を含めてはいけない
// （申し送り #28）。定義を 2 箇所に書くと片方だけ直す事故になるのでここを唯一の
// 情報源にする。
export const unitProject = {
  ...common,
  displayName: 'unit',
  rootDir: '.',
  testMatch: ['<rootDir>/src/**/*.spec.ts'],
};

const config: Config = {
  rootDir: '.',
  // 手順書 §4.1 は種別ごとにファイル名を分ける（*.int-spec.ts / *.e2e-spec.ts）。
  // ここを 1 つの testMatch で束ねると、`*.spec.ts` は `-spec.ts` 終わりの
  // ファイルにマッチしないため、統合テストと e2e が黙って実行されない。
  // 「テストを置いたのに Jest が拾わず緑のまま」は、このリポジトリが
  // 繰り返し踏んでいる「緑と守っているは別物」の型そのものである。
  projects: [
    unitProject,
    {
      // 以下 integration / e2e は既存のまま（変更しない）
```

既存の `integration` / `e2e` のブロックと `collectCoverageFrom` / `coverageDirectory` は触らない。

- [ ] **Step 3: `apps/api/jest.stryker.config.ts` を作る**

```ts
import type { Config } from 'jest';
import { unitProject } from './jest.config';

// Stryker が使う Jest 設定。unit プロジェクトだけを持つ。
//
// jest.config.ts をそのまま渡すと integration / e2e が含まれ、
// test/setup-db.ts の Testcontainers が **mutant の数だけ** PostgreSQL コンテナを
// 起動する（申し送り #28）。手順書 §5.2 は `jest: { configFile: 'jest.config.ts' }`
// と書いており、この相互作用に触れていない。逸脱の理由は
// docs/superpowers/phase0-findings.md に記録する。
const config: Config = {
  ...unitProject,
  rootDir: '.',
};

export default config;
```

- [ ] **Step 4: `apps/api/tsconfig.json` の `include` に追加する**

```jsonc
  "include": ["src/**/*.ts", "test/**/*.ts", "prisma/**/*.ts", "jest.config.ts", "jest.stryker.config.ts"]
```

**これを忘れると `l1-lint` が壊れる。** ESLint の `projectService: true` は既定名 `tsconfig.json` 経由でしか設定ファイルを解決しないため、include に無い `.ts` ファイルは型情報付きルールで解決できずエラーになる（§1.37 で実際に踏んでいる）。

- [ ] **Step 5: unit だけが列挙されることを実測する**

```bash
pnpm --filter api exec jest -c jest.stryker.config.ts --listTests
```

期待: `src/**/*.spec.ts` の 3 ファイル（`auth/auth.guard.spec.ts` / `discount/discount.spec.ts` / `orders/orders.service.spec.ts`）だけが出る。**`test/orders.int-spec.ts` と `test/orders.e2e-spec.ts` が出てはいけない。** 出たら Step 2〜3 が効いていない。

- [ ] **Step 6: `apps/api/stryker.config.json` を作る**

```jsonc
{
  "$schema": "../../node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "testRunner": "jest",
  "jest": { "configFile": "jest.stryker.config.ts" },
  "coverageAnalysis": "perTest",
  "mutate": [
    "src/**/*.ts",
    "!src/**/*.spec.ts",
    "!src/main.ts",
    "!src/openapi.ts",
    "!src/**/*.module.ts"
  ],
  "incremental": false,
  "thresholds": { "high": 80, "low": 60, "break": null },
  "reporters": ["clear-text", "html", "json"]
}
```

手順書 §5.2 からの差分は 5 点。**すべて意図的である。**

1. `$schema` のパスを `../../node_modules/...` にした（pnpm workspace では依存はルートの `node_modules` に巻き上げられ、`apps/api/node_modules/@stryker-mutator/core` はシンボリックリンクで解決できる場合もあるが、`../../` のほうが確実。解決できなければエディタの補完が効かないだけでゲートには影響しない）
2. `jest.configFile` を `jest.stryker.config.ts` にした（申し送り #28）
3. `mutate` に `"!src/openapi.ts"` を足した（申し送り #29。OpenAPI 生成のエントリポイントでテストが直接叩かない）
4. `incremental` を `false` にした（逸脱表を参照）。手順書は `true` + `incrementalFile`
5. `thresholds.break` を `null` にした（手順書 §5.5 の手順 1「まず `break: null` で計測のみ実施し、現状値を把握する」に従う。Task 4 で実測値から決める）

**`toOrderResponse`（`src/orders/orders.service.ts` のファイルローカル関数）は除外しない**（申し送り #14）。`src/orders/dto/*.ts` も除外しない（手順書は `*.module.ts` とエントリポイントと生成コードだけを除外対象に挙げている。DTO のデコレータに生き残る mutant があるならそれも実測データである）。

- [ ] **Step 7: フル実行してスコアを実測する**

```bash
pnpm turbo generate                       # Prisma Client の生成を先行させる（申し送り #13）
pnpm --filter api exec stryker run 2>&1 | tee /tmp/stryker-api-full.log
tail -n 40 /tmp/stryker-api-full.log
```

`turbo generate` を先に走らせるのは、Stryker を直叩きすると `turbo.json` の `dependsOn` を経由せず `@prisma/client` の生成物が無い状態で走るため（申し送り #13）。

記録すること（タスクレポートに数値で残す）:
- **Mutation score（全体）**、および `clear-text` レポーターが出すファイル別スコア
- Killed / Survived / No coverage / Timeout / Error の各件数
- 所要時間（**絶対値を根拠に判断はしない**。内訳の構造として記録する）
- 生き残った mutant のうち、`dto/` と `prisma.service.ts` に属するものの件数（除外方針の判断材料。申し送り #29）

Stryker がそもそも起動しない場合（ts-jest との噛み合わせ、instrumenter のエラーなど）は、**エラー全文と切り分け（どの段階で落ちたか）をレポートに残す。** 推測で設定をいじって「動いたように見える」状態を作らない。

- [ ] **Step 8: 既存ゲートの回帰を確認する**

依存を 1 つ足すと別の層のゲートが赤くなる（Phase 3 で 2 回起きた。§1.34 / §1.39）。新しい `.ts` ファイルを足すと `l1-lint` / `l1-typecheck` が壊れる（§1.36 / §1.37）。両方を実測で潰す。

```bash
./scripts/gates/l2-install.sh   ; echo "l2-install=$?"
./scripts/gates/l1-typecheck.sh ; echo "l1-typecheck=$?"
./scripts/gates/l1-lint.sh      ; echo "l1-lint=$?"
./scripts/gates/l2-osv.sh       ; echo "l2-osv=$?"
./scripts/gates/l3-test.sh      ; echo "l3-test=$?"
```

期待: すべて `0`。

`l2-osv` が `1` を返したら（Stryker の依存ツリーに High 以上の脆弱性がある）、**`overrides` を自分の判断で足さずに、脆弱性 ID・該当パッケージ・修正版の公開日を添えて人間の判断を仰いで停止する**（Global Constraints / 決定 3）。

- [ ] **Step 9: コミットする**

```bash
git add apps/api/package.json apps/api/jest.config.ts apps/api/jest.stryker.config.ts \
        apps/api/stryker.config.json apps/api/tsconfig.json pnpm-lock.yaml
git commit -m "feat(l4): apps/api に Stryker を導入し break: null でスコアを実測"
```

---

## Task 2: web に Stryker を入れ、フル実行スコアを実測する

**Files:**
- Modify: `apps/web/package.json`（devDependencies）
- Modify: `pnpm-lock.yaml`
- Create: `apps/web/stryker.config.json`

**Interfaces:**
- Consumes: なし（Task 1 とは独立。ただし `pnpm-lock.yaml` を触るので Task 1 の後に実行する）
- Produces: web のフル実行ミューテーションスコア（Task 4 が web 側の閾値を決めるのに使う数値。ゲートには入らない）

- [ ] **Step 1: 依存を追加する**

```bash
pnpm --filter web add -D @stryker-mutator/core@9.6.1 @stryker-mutator/vitest-runner@9.6.1
```

`@stryker-mutator/vitest-runner@9.6.1` の peer は `vitest: '>=2.0.0'` なので、このリポジトリの vitest 4.1.10 は宣言上は満たす（実測前の情報として。実際に動くかは Step 3 で確かめる）。キャレットが付いたら外す。拒否されたら Task 1 Step 1 と同じく人間の判断を仰ぐ。

- [ ] **Step 2: `apps/web/stryker.config.json` を手順書 §5.2 の逐語で作る**

**まず手順書どおりに書く。** 直すのは実測した後（Step 4）。

```jsonc
{
  "testRunner": "vitest",
  "vitest": { "configFile": "vitest.config.ts", "related": true },
  "mutate": ["src/**/*.{ts,tsx}", "!src/**/*.test.{ts,tsx}", "!src/main.tsx"],
  "incremental": false,
  "thresholds": { "high": 80, "low": 60, "break": null }
}
```

手順書 §5.2 の web 設定からの差分は 2 点のみ: `incremental` を `false`（逸脱表）、`break` を `null`（§5.5 手順 1）。それ以外は 1 文字も変えない。

- [ ] **Step 3: フル実行して、何が起きるかを実測する**

```bash
pnpm --filter web exec stryker run 2>&1 | tee /tmp/stryker-web-full.log
tail -n 60 /tmp/stryker-web-full.log
```

**この Step の目的はスコアを得ることではなく、手順書 §5.2 の web 設定が実際にどう振る舞うかを観測することである。** 少なくとも次の 3 点を確認してレポートに書く。

1. **`vitest.related` は有効なオプションか。** 不明なオプションなら Stryker は「Unknown stryker config option」の警告を出す。出たらその文字列をそのまま記録する（手順書の記述誤りの候補）
2. **`src/**/*.{ts,tsx}` が `.d.ts` を拾うか。** このリポジトリの `apps/web/src` には生成物 `api/schema.d.ts` と `env.d.ts` がある。手順書 §5.2 の本文は「除外すべき対象：…生成コード」と書いているが、**glob は `.d.ts` を除外していない**。拾われた場合、mutant が作られるのか 0 件なのかエラーになるのかを記録する
3. **vitest 4.1.10 で mutant ごとのテスト実行が成立するか。** 成立しなければ、エラー全文とどの段階で落ちたか（設定検証 / 初回テスト実行 / instrumenter）を切り分けて記録する

- [ ] **Step 4: 観測結果に応じて最小修正を入れる**

Step 3 で「手順書どおりでは何も測れない」ことが分かった場合に限り、**最小の修正**を入れる。修正するたびに、その理由を設定ファイルのコメントに書く（このリポジトリの `.json` 設定は `jsonc` として扱っており、他のゲート設定も同じ方針でコメントを入れている）。

想定される修正は次の 2 つだけである。これ以外の修正が必要になったら、レポートに理由を書いてから入れる。

```jsonc
  // 生成物と型宣言のみのファイルを除外する。手順書 §5.2 の本文は「生成コードは除外」と
  // 書いているが glob（src/**/*.{ts,tsx}）は .d.ts を除外していない。§1.45 に記録。
  "mutate": [
    "src/**/*.{ts,tsx}",
    "!src/**/*.test.{ts,tsx}",
    "!src/main.tsx",
    "!src/**/*.d.ts"
  ],
```

```jsonc
  // 手順書 §5.2 の `related: true` は Stryker 9.6.1 に存在しないオプションで、
  // 「Unknown stryker config option」の警告になる（実測）。§1.45 に記録。
  "vitest": { "configFile": "vitest.config.ts" },
```

**web 側が最後まで動かない場合は、それを結論として受け入れる。** 設定ファイルは「何が起きたか」のコメント付きで残し、findings に記録して次のタスクへ進む。**api 側の進行をブロックしない**（決定 1）。

- [ ] **Step 5: スコアを記録する**

動いた場合、Task 1 Step 7 と同じ項目（全体スコア / ファイル別スコア / Killed・Survived・No coverage・Timeout・Error の件数）を記録する。`apps/web/src` の実装は `App.tsx` / `api/client.ts` / `features/orders/OrderList.tsx` / `features/orders/orderTotal.ts` の 4 ファイルなので、**どのファイルの mutant が生き残ったか**まで書く（`client.ts` は `fetch` を叩くので単体テストが薄い見込み。それが実測で裏付くかどうか）。

- [ ] **Step 6: 既存ゲートの回帰を確認する**

```bash
./scripts/gates/l2-install.sh   ; echo "l2-install=$?"
./scripts/gates/l1-typecheck.sh ; echo "l1-typecheck=$?"
./scripts/gates/l1-lint.sh      ; echo "l1-lint=$?"
./scripts/gates/l2-osv.sh       ; echo "l2-osv=$?"
./scripts/gates/l3-test.sh      ; echo "l3-test=$?"
```

期待: すべて `0`。`l2-osv` が `1` なら Task 1 Step 8 と同じ手順で人間の判断を仰ぐ。

- [ ] **Step 7: コミットする**

```bash
git add apps/web/package.json apps/web/stryker.config.json pnpm-lock.yaml
git commit -m "feat(l4): apps/web に Stryker を導入し、手順書 §5.2 の web 設定を実測"
```

---

## Task 3: `scripts/stryker-diff.sh` を手順書逐語で作り、仮説 4 を実測してから最小修正する

**Files:**
- Create: `scripts/stryker-diff.sh`

**Interfaces:**
- Consumes: `apps/api/stryker.config.json`（Task 1）
- Produces: `scripts/stryker-diff.sh`。挙動の契約は「変更が無ければ標準出力に `L4_MUTATE_FILES=(none)` を出して exit 0 / 変更があれば `L4_MUTATE_FILES=<カンマ区切り>` を出して `stryker run --mutate` の exit code を返す」。Task 4 の `l4-mutation.sh` がこれを呼ぶ

**このタスクの本題は仮説 4 の検証である。** 設計書 §7 の仮説 4 はこう書いている:

> `scripts/stryker-diff.sh` はパスのずれで空振りする。`git diff` はリポジトリルート相対を返すが `pnpm --filter api exec` は `apps/api` をカレントにする

**先に手順書どおりのものを作って実測し、その後で直す。** 順序を逆にすると仮説 4 に実測の根拠を与えられない。

- [ ] **Step 1: 手順書 §5.3 を逐語で写す**

`scripts/stryker-diff.sh` を作る。**この Step では手順書の内容を 1 文字も変えない**（`corepack enable` はそもそも §5.3 に無いので問題にならない）。

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

```bash
chmod +x scripts/stryker-diff.sh
```

- [ ] **Step 2: 仮説 4 を実測する（`src` の 1 階層下のファイルを変更した場合）**

一時ブランチを切って `apps/api/src/discount/discount.ts` を変更し、手順書どおりのスクリプトを走らせる。**作業ツリーが汚れていないことを先に確認する。**

```bash
git status --porcelain          # 空であることを確認
git checkout -b tmp/hypothesis4
printf '\n// 仮説 4 の実測用。このブランチは破棄する\n' >> apps/api/src/discount/discount.ts
git add apps/api/src/discount/discount.ts
git commit -m "tmp: 仮説 4 の実測"
./scripts/stryker-diff.sh 2>&1 | tee /tmp/hypothesis4-nested.log
echo "exit=$?"
```

記録すること:
- `git diff --name-only ... -- 'apps/api/src/**/*.ts'` が返した文字列（**リポジトリルート相対か、パッケージ相対か**）
- Stryker に渡った `--mutate` の値
- Stryker が「0 mutants」「ファイルが見つからない」「正常に N 個の mutant を作った」のどれになったか（**ここが仮説 4 の結論**）
- exit code

- [ ] **Step 3: pathspec が `src` 直下のファイルを取りこぼすかを実測する**

`§1.23` で、git の pathspec `'**/package.json'` がルート直下の `package.json` に一致しないことを実測している。同じ理屈で `'apps/api/src/**/*.ts'` は **`src` 直下**（`app.module.ts` / `main.ts` / `openapi.ts`）に一致しない可能性がある。同じ一時ブランチで確かめる。

```bash
printf '\n// 仮説 4 の実測用（src 直下）\n' >> apps/api/src/app.module.ts
git add apps/api/src/app.module.ts
git commit -m "tmp: pathspec の実測（src 直下）"
git diff --name-only "main...HEAD" -- 'apps/api/src/**/*.ts'
git diff --name-only "main...HEAD" -- 'apps/api/src'
```

記録すること: 2 つの pathspec が返すファイル一覧の差。前者に `apps/api/src/app.module.ts` が出なければ、**手順書 §5.3 の pathspec は `src` 直下の変更を取りこぼす**（`app.module.ts` は `mutate` から除外しているので実害は小さいが、記述の誤りとして記録する）。

- [ ] **Step 4: 一時ブランチを破棄する**

```bash
git checkout main
git branch -D tmp/hypothesis4
git status --porcelain          # 空であることを確認
```

- [ ] **Step 5: 実測に基づく最小修正を入れる**

Step 2 / Step 3 の実測を踏まえて `scripts/stryker-diff.sh` を書き直す。**「何も見ずに緑」を残さないための最小修正**であり、§1.15（`semgrep ci` → `semgrep scan`）で確立した扱いと同じである。

```bash
#!/usr/bin/env bash
# 手順書 §5.3 の差分限定ミューテーション実行。
#
# 手順書の原文からの変更点は 4 つ。1・2・4 は「手順書どおりでは何も測れない／
# 区別できない」ことを実測してから入れた修正である。3（GATE_BASE_REF への移行）は
# 実測した失敗の再現ではなく、検証ハーネスの既存規約（l2-new-deps.sh）に合わせた
# 予防的な変更である（fetch 自体は実測時に成功しており、ネットワーク障害そのものは
# 再現していない）（詳細は docs/superpowers/phase0-findings.md §1.45 以降）。
#
#   1. --mutate に渡すパスをパッケージ相対に直す（仮説 4）。git diff はリポジトリ
#      ルート相対（apps/api/src/...）を返すが、pnpm --filter api exec は apps/api を
#      カレントにするので、そのまま渡すと apps/api/apps/api/src/... を探して空振りする。
#   2. pathspec を 'apps/api/src' にする。'apps/api/src/**/*.ts' は git の pathspec
#      では src 直下のファイルに一致しない（§1.23 と同型）。
#   3. git fetch を廃し、比較対象を GATE_BASE_REF で受け取る。検証ハーネスは main から
#      切ったローカルの検証ブランチ上で走るので origin への fetch は不要で、
#      ネットワーク障害をゲートの失敗に化けさせるだけである（l2-new-deps.sh と同じ方針）。
#   4. ミューテート対象のファイル名を必ず標準出力に出す。差分 0 件でスキップした緑と
#      「実際にミューテートして生き残らなかった」緑を、ログから区別できるようにする
#      （§1.43 の「何が走ったか分からない緑」を作らないため）。
set -euo pipefail

BASE_REF="${GATE_BASE_REF:-origin/${BASE_BRANCH:-main}}"
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  printf 'stryker-diff: 比較対象の ref が見つかりません: %s\n' "$BASE_REF" >&2
  exit 3
fi

CHANGED=$(git diff --name-only "$BASE_REF...HEAD" -- 'apps/api/src' \
  | grep -E '\.ts$' | grep -v '\.spec\.ts$' || true)

if [ -z "$CHANGED" ]; then
  printf 'L4_MUTATE_FILES=(none)\n'
  echo "変更なし。スキップします。"
  exit 0
fi

MUTATE=$(printf '%s\n' "$CHANGED" | sed 's|^apps/api/||' | paste -sd, -)
printf 'L4_MUTATE_FILES=%s\n' "$MUTATE"
pnpm --filter api exec stryker run --mutate "$MUTATE"
```

`exit 3` を使うのは、`l4-mutation.sh` 側で「Stryker が動いた結果の 1」と「そもそも比較対象が無くて動かせなかった」を混ぜないため。ゲート側は 3 を error(2) に写像する（Task 4）。

- [ ] **Step 6: 修正後のスクリプトで、実際に mutant が作られることを実測する**

Step 2 と同じ手順を修正後のスクリプトで繰り返す。今回は**中身のある変更**を入れる（コメント追加だけでは mutant が変わらないため、`applyDiscount` に未テストの分岐を足す）。

```bash
git checkout -b tmp/verify-diff-script
```

`apps/api/src/discount/discount.ts` の `applyDiscount` の先頭に次を足す:

```ts
  if (price > 1_000_000) {
    return price;
  }
```

```bash
pnpm --filter api exec jest -c jest.stryker.config.ts   # 既存テストが緑であることを先に確認
git add apps/api/src/discount/discount.ts
git commit -m "tmp: 差分スクリプトの動作確認"
GATE_BASE_REF=main ./scripts/stryker-diff.sh 2>&1 | tee /tmp/diff-script-verify.log
echo "exit=$?"
git checkout main && git branch -D tmp/verify-diff-script
```

期待: `L4_MUTATE_FILES=src/discount/discount.ts` が出て、Stryker が `discount.ts` の mutant を作り、**追加した未テストの分岐に生き残り（Survived）が出る**。生き残りの件数とスコアを記録する。`break` はまだ `null` なので exit code は 0 になる（Task 4 で閾値を入れてからが赤確認である）。

- [ ] **Step 7: shellcheck を通してコミットする**

```bash
shellcheck scripts/gates/*.sh scripts/stryker-diff.sh verification/*.sh
echo "shellcheck=$?"
git status --porcelain          # 空であることを確認（一時ブランチが残っていないこと）
git add scripts/stryker-diff.sh
git commit -m "feat(l4): 手順書 §5.3 の差分限定スクリプトを実装（仮説 4 の実測を反映）"
```

期待: `shellcheck=0`、指摘 0。

---

## Task 4: `l4-mutation` ゲートを作り、閾値を決めて赤確認する

**Files:**
- Create: `scripts/gates/l4-mutation.sh`
- Modify: `scripts/gates/gates.list.sh:13`（`GATE_ORDER`）
- Modify: `apps/api/stryker.config.json`（`thresholds.break` を実測値から決めた値に）
- Modify: `apps/web/stryker.config.json`（同じ。web はゲートに入らないが、nightly のために閾値を入れる）

**Interfaces:**
- Consumes: `scripts/stryker-diff.sh`（Task 3）、api / web のフル実行スコア（Task 1 / Task 2）
- Produces: `scripts/gates/l4-mutation.sh`（exit 0/1/2）、`GATE_ORDER` に `l4-mutation` が末尾で入った状態

- [ ] **Step 1: `scripts/gates/l4-mutation.sh` を書く**

```bash
#!/usr/bin/env bash
# L4: ミューテーションテスト（手順書 §5）
#
# 手順書 §7 の cloudbuild は L4 のステップを `./scripts/stryker-diff.sh` の呼び出し
# だけで書いている。ここもそれに合わせ、差分限定の実行を薄く包んで exit code を
# 3 値へ正規化するだけにする。
#
# Docker は要らない。Stryker が回すのは Jest の unit プロジェクトだけで
# （apps/api/jest.stryker.config.ts）、Testcontainers を使う integration / e2e は
# 含まないため（申し送り #28）。gate_require_docker を呼ばないのは意図的である。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd pnpm
# ガード対象と同じスコープで呼ぶ（§1.12）。pnpm のフィルタは exec より前に置く必要がある。
gate_require_runnable 'stryker' pnpm --filter api exec stryker --version

_log=$(mktemp)
./scripts/stryker-diff.sh 2>&1 | tee "$_log"
raw="${PIPESTATUS[0]}"

if [ "$raw" -eq 0 ]; then
  rm -f "$_log"
  exit "$GATE_PASS"
fi

# Stryker は「閾値割れ」も「初回テスト実行の失敗」も「設定エラー」も同じ 1 を返す。
# 閾値割れのときだけログに出る文字列で切り分ける（実測した文字列を Step 4 でここに
# 固定する）。初回テスト実行の失敗を fail に写像すると、「テストが落ちている」が
# 「ミューテーションテストが空虚なテストを検出した」になる（§1.44 と同じ型の事故）。
#
# stryker-diff.sh が返す 3（比較対象の ref が無い）はこのパターンに一致しないので
# error(2) に落ちる。これは意図した写像である。
gate_fail_if_matches "$_log" 'PLACEHOLDER_実測した文字列に置き換える'
```

```bash
chmod +x scripts/gates/l4-mutation.sh
```

- [ ] **Step 2: 閾値を決める**

手順書 §5.5 の手順 2「現状値の少し下（例：現状 45% なら 40%）を `break` に設定」に従う。Task 1 / Task 2 で実測したフル実行スコアを使う。

- api の `break` = api のフル実行スコアを 5 ポイント下回る、5 の倍数に丸めた値（例: 実測 68.4% → `65`）
- web の `break` = 同じ規則（web が動かなかった場合は `null` のまま残し、その理由をコメントに書く）
- `high` / `low` は手順書の `80` / `60` を変えない（表示用の閾値であり、exit code には影響しない）

決めた値と、そこから見た**手順書の推奨 `break: 60` が現実的かどうか**をレポートに書く（設計書 §10 が Phase 4 の眼目として挙げている検証データ）。

`apps/api/stryker.config.json` を書き換える:

```jsonc
  // 手順書 §5.5 の手順どおり、break: null でフル実行した実測値（<実測値>%）の
  // 少し下に置く。手順書が推奨する 60 との差は §1.45 以降に記録する。
  "thresholds": { "high": 80, "low": 60, "break": <決めた値> },
```

- [ ] **Step 3: `GATE_ORDER` に足す**

`scripts/gates/gates.list.sh` の 1 箇所だけを直す（申し送り #18 で集約済み、#30）。

```bash
GATE_ORDER=(l2-install l1-typecheck l1-lint l2-semgrep l2-osv l2-gitleaks l3-test l3-openapi-drift l4-mutation)
```

**`l3-e2e-web`（Playwright）を一緒に拾わないこと。** 意図的に `GATE_ORDER` の外に置いてある（§1.35）。`l4-mutation` は `l3-test` より後ろに置く（Task 5 の依存スキップが実行順に依存する）。

- [ ] **Step 4: 赤確認 ①（閾値割れ → fail(1)）**

**「実際に起こりうる壊し方」で赤確認する**（§1.44）。ここでの現実的な壊し方は「実装に分岐を足したが、その分岐を検証するテストを書かなかった」である。

```bash
git checkout -b tmp/red-check-threshold
```

`apps/api/src/discount/discount.ts` の `applyDiscount` の先頭に足す:

```ts
  if (price > 1_000_000) {
    return price;
  }
```

```bash
git add apps/api/src/discount/discount.ts
git commit -m "tmp: 閾値割れの赤確認"
GATE_BASE_REF=main ./scripts/gates/l4-mutation.sh; echo "l4-mutation=$?"
./scripts/gates/l3-test.sh; echo "l3-test=$?"
```

期待: **`l4-mutation=1`**（fail）かつ **`l3-test=0`**（pass）。これが成り立って初めて「L3 が通るのに L4 だけが止める」を示したことになる（設計書 §9 の L4 セクション）。

**`l4-mutation=1` が出ない場合の対処**:
- `2` が返った → Step 1 の `gate_fail_if_matches` のパターンが実測の文字列と合っていない。ログ（`/tmp` の mktemp ファイルではなく `GATE_BASE_REF=main ./scripts/gates/l4-mutation.sh 2>&1 | tee /tmp/red-check.log` で取り直す）から Stryker が閾値割れのときに出す実際の文字列を読み、Step 1 の `PLACEHOLDER_...` をその文字列に置き換える。**推測で書かない。実測した文字列だけを入れる**
- `0` が返った → 追加した分岐の mutant が閾値を割るほどスコアを下げていない。生き残り件数と `discount.ts` 単体のスコアをレポートに記録し、**未テストの分岐をもう 1 つ足す**（`if (price < 0) { return 0; }` など）。それでも 0 なら、**差分実行のスコアはフル実行の閾値では割れない**ことの実測データになるので、そのままレポートに書いて次の Step へ進む（設定をこじつけて赤くしない）

```bash
git checkout main && git branch -D tmp/red-check-threshold
```

- [ ] **Step 5: 赤確認 ②（初回テスト実行の失敗 → error(2)、fail(1) ではないこと）**

**これが本タスクで最も重要な確認である。** Stryker は初回テスト実行が緑でないとミューテーションを始められない。その状態を fail(1) と記録すると、「テストが落ちている」が「L4 が空虚なテストを検出した」になる。

```bash
git checkout -b tmp/red-check-error
git apply verification/cases/L3-01-broken-logic/case.patch
git add -A && git commit -m "tmp: 初回テスト実行が赤い状態の写像を確認"
GATE_BASE_REF=main ./scripts/gates/l4-mutation.sh 2>&1 | tee /tmp/red-check-error.log
echo "l4-mutation=${PIPESTATUS[0]}"
./scripts/gates/l3-test.sh; echo "l3-test=$?"
git checkout main && git branch -D tmp/red-check-error
```

期待: **`l4-mutation=2`**（error）かつ **`l3-test=1`**（fail）。

ログに出た Stryker のメッセージ（初回テスト実行の失敗を示す行）を**そのまま**レポートに記録する。Task 5 の依存スキップはこの実測を根拠にする。

`l4-mutation=1` が返った場合は Step 1 のパターンが広すぎる（初回テスト実行の失敗メッセージにも一致してしまっている）。パターンを狭めて再確認する。

- [ ] **Step 6: `gates.test.sh` を通す**

`gates.test.sh` は `GATE_ORDER` をループするので、`l4-mutation` の pass 経路（クリーンなツリー = 差分 0 件でスキップ）・error 経路（`PATH` を絞って pnpm を消す）・呼び出し位置非依存の 3 つが自動で追加される。**Docker デーモン不在のループ（`for gate in l2-semgrep l2-osv l2-gitleaks l3-test`）には `l4-mutation` を足さない**（Docker を使わないゲートなので、そこに入れると必ず失敗する）。

```bash
./scripts/gates/gates.test.sh
echo "gates.test=$?"
```

期待: `gates.test=0`、**38 件成功**（Phase 3 は 35 件。`l4-mutation` の pass / error / 呼び出し位置非依存で +3）。件数が合わなければ理由を確認する。

（当初この計画は「30 件（Phase 3 は 27 件）」と書いていたが、27 件は **Phase 2** の実測値だった。Phase 3 の受け入れ記録は 35 件である。実装時に `phase0-findings.md` §4 で確認して訂正した。）

- [ ] **Step 7: クリーンなツリーで全ゲートが緑であることを確認する**

```bash
for g in $(bash -c 'source scripts/gates/gates.list.sh; echo "${GATE_ORDER[@]}"'); do
  "./scripts/gates/$g.sh" >/dev/null 2>&1; printf '%s=%s\n' "$g" "$?"
done
shellcheck scripts/gates/*.sh scripts/stryker-diff.sh verification/*.sh; echo "shellcheck=$?"
```

期待: 9 本すべて `0`、`shellcheck=0`。

- [ ] **Step 8: コミットする**

```bash
git status --porcelain          # 一時ブランチの残骸が無いこと
git add scripts/gates/l4-mutation.sh scripts/gates/gates.list.sh \
        apps/api/stryker.config.json apps/web/stryker.config.json
git commit -m "feat(l4): l4-mutation ゲートを追加し、実測値から閾値を決めた"
```

---

## Task 5: ハーネスに `l4-mutation` を組み込み、既存 14 ケースの退行を確認する

**Files:**
- Modify: `verification/run-case.sh:170-176`（`l3-test` が pass でないときは `l4-mutation` を実行しない）
- Modify: `verification/cases/*/expect.yml`（13 ケース。`L2-01-phantom-package` は除く）
- Modify: `verification/RESULTS.md`（`run-all.sh` の生成物）

**Interfaces:**
- Consumes: `GATE_ORDER` に `l4-mutation` が入った状態（Task 4）、Task 4 Step 5 の実測（初回テスト実行の失敗 → error(2)）
- Produces: 14 ケースすべての `expect.yml` が実測と一致し、`RESULTS.md` の判定が Phase 3 から退行していない状態

**このタスクはハーネス自身を変更する。** ハーネスを変更したら、既に `match` だったケースを再実行して退行していないか確かめる（Phase 1 で実際に退行させた）。

- [ ] **Step 1: 依存スキップの規則を `run-case.sh` に入れる**

Task 4 Step 5 で実測したとおり、`l3-test` が赤いケースでは `l4-mutation` は error(2) を返す。判定上これを放置すると、**該当する 5 ケース（L1-03 / L2-02 / L2-05 / L3-01 / L3-03）が全部 ⚠️ 判定不能になる**（`judge.mjs` は error が 1 つでもあれば `claimVerdict` を `inconclusive` にする）。Phase 3 まで ✅ だったケースが判定を失うので、これはハーネスの退行である。

`verification/run-case.sh` の 170〜176 行を次に置き換える。

```bash
# l4-mutation は l3-test が緑であることを前提にする。Stryker は初回テスト実行が
# 緑でないとミューテーションを始められず、非ゼロで終わる（Task 4 Step 5 で実測）。
# これを fail と記録すれば「テストが落ちている」が「L4 が空虚なテストを検出した」に
# なり、error と記録すればケース全体が判定不能（⚠️）になる。どちらも誤りなので、
# l3-test が pass でないケースでは l4-mutation を実行せず TSV にも書かない。
# l2-install が失敗したら後続を打ち切るのと同じ理由づけである（設計書 §8.2）。
#
# スキップしたことは stderr に必ず出す。黙って飛ばすと「走らなかった緑」と
# 「走って通った緑」が区別できなくなる（§1.43）。
l3_test_code=""
if ! run_gate "${GATE_ORDER[0]}"; then
  printf '%s が pass しなかったため後続のブロックゲートを打ち切りました\n' "${GATE_ORDER[0]}" >&2
else
  for gate in "${GATE_ORDER[@]:1}"; do
    if [ "$gate" = "l4-mutation" ] && [ "$l3_test_code" != "0" ]; then
      printf '  %-20s skipped（l3-test が pass しなかったため実行しない）\n' "$gate" >&2
      continue
    fi
    run_gate "$gate"
    gate_code=$?
    if [ "$gate" = "l3-test" ]; then
      l3_test_code="$gate_code"
    fi
  done
fi
```

bash 3.2 なので連想配列は使えない。`l4-mutation` と `l3-test` を直に名指しするのは `l2-install` を `GATE_ORDER[0]` として特別扱いしているのと同じ形である。

- [ ] **Step 2: shellcheck を通す**

```bash
shellcheck scripts/gates/*.sh scripts/stryker-diff.sh verification/*.sh
echo "shellcheck=$?"
```

期待: `shellcheck=0`。

- [ ] **Step 3: ハーネスの変更をコミットする**

**`run-case.sh` は作業ツリーが汚れていると exit 2 で止まる。** 次の Step でケースを実行するので、ここで先にコミットする。

```bash
git add verification/run-case.sh
git commit -m "feat(l4): l3-test が赤いケースでは l4-mutation を実行しない依存スキップを入れる"
```

- [ ] **Step 4: `l3-test` が緑のケース 1 本で実測して `expect.yml` を決める**

まず 1 本だけ回して、`l4-mutation` が実際に何を返すかを見る。`L1-04-unused-disable` は `apps/api/src/discount/discount.ts` を触るので、差分限定の Stryker が**実際にミューテートする**ケースである。

```bash
./verification/run-case.sh L1-04-unused-disable 2>&1 | tail -n 30
```

stderr の `l4-mutation exit=N` を読む。**`0` でも `1` でもありうる**:

- `0` = `discount.ts` 単体のスコアが閾値を上回った
- `1` = 下回った。**これは「1 ファイルだけを対象にした差分実行に、フル実行から決めた閾値を当てている」ことの帰結**であり、手順書 §5.3 と §5.5 の組み合わせが持つ構造的な問題である（母数が変わるとスコアの意味が変わる）。§1.45 以降に記録する対象

どちらであっても、**実測値を `expect.yml` に書く**（`expect` は実測に合わせて更新してよい。`claimed_layer` は触らない）。

- [ ] **Step 5: 13 ケースの `expect.yml` に `l4-mutation` の行を足す**

`l3-test: pass` のケース（8 本）には `l4-mutation` の実測値を書く。

```yaml
  l3-openapi-drift: pass
  l4-mutation: pass          # ← 実測値。fail なら fail と書く
```

`l3-test: fail` のケース（5 本: L1-03 / L2-02 / L2-05 / L3-01 / L3-03）には**行を足さない**。Step 1 のスキップ規則で実行されないため、書くと `judge.mjs` が `not-run` の mismatch を出す。代わりに理由をコメントで残す。

```yaml
  l3-openapi-drift: pass
  # l4-mutation はここに書かない。l3-test が fail するケースでは Stryker の初回テスト
  # 実行が緑にならず、ハーネスがゲートをスキップする（run-case.sh の依存スキップ）。
```

`L2-01-phantom-package` は `l2-install` が fail して後続を打ち切るので、現状の 2 ゲート分のまま触らない。

各ケースの `l3-test` の期待値は次のとおり（`case.patch` が触るファイルと併せて）。

| ケース | `l3-test` | `case.patch` が触るファイル | `l4-mutation` の行 |
|---|---|---|---|
| L1-01-eslint-disable-abuse | pass | `apps/api/src/orders/orders.service.ts` | 実測値を書く（ミューテート実行あり） |
| L1-02-explicit-any | pass | `apps/web/src/api/client.ts` | 実測値を書く（api の差分 0 件 → スキップ → pass 見込み） |
| L1-03-floating-promise | fail | `apps/api/src/orders/orders.service.ts` | **書かない** |
| L1-04-unused-disable | pass | `apps/api/src/discount/discount.ts` | 実測値を書く（ミューテート実行あり） |
| L1-05-unchecked-index | pass | `apps/web/src/features/orders/orderTotal.ts` | 実測値を書く（api の差分 0 件） |
| L1-06-web-imports-api | pass | `apps/web/src/features/orders/orderTotal.ts` | 実測値を書く（api の差分 0 件） |
| L2-01-phantom-package | （打ち切り） | `apps/api/package.json`, `.../orders.service.ts` | 触らない |
| L2-02-guard-missing | fail | `apps/api/src/orders/orders.controller.ts` | **書かない** |
| L2-03-hardcoded-secret | pass | `apps/api/src/orders/orders.service.ts` | 実測値を書く（ミューテート実行あり） |
| L2-04-new-dependency | pass | `apps/api/package.json`, `.../orders.service.ts`, `pnpm-lock.yaml` | 実測値を書く（ミューテート実行あり） |
| L2-05-sql-injection | fail | `apps/api/src/orders/orders.service.ts` | **書かない** |
| L3-01-broken-logic | fail | `apps/api/src/discount/discount.ts` | **書かない** |
| L3-02-openapi-drift | pass | `apps/api/src/orders/dto/order-response.dto.ts` | 実測値を書く（ミューテート実行あり） |
| L3-03-authz-bypass | fail | `.../orders.controller.ts`, `.../orders.service.ts` | **書かない** |

- [ ] **Step 6: コミットする**

```bash
git add verification/cases/*/expect.yml
git commit -m "test(l4): 既存 14 ケースの期待値に l4-mutation の実測値を反映"
```

**コミットしてから次の Step へ進む。** `run-all.sh` は作業ツリーが汚れていると各ケースが exit 2 で止まる。

- [ ] **Step 7: `run-all.sh` で 14 ケースの退行を確認する（バックグラウンド）**

```bash
./verification/run-all.sh > /tmp/run-all-task5.log 2>&1
```

**必ずバックグラウンドで実行する**（Bash ツールのタイムアウト上限 10 分を超える実測がある）。完了後に確認する:

```bash
grep -E '^\| (L1|L2|L3)' verification/RESULTS.md
grep -E '判定不能' verification/RESULTS.md; echo "inconclusive_grep=$?"
grep -E '^全体の所要時間' /tmp/run-all-task5.log
```

期待:
- **`RESULTS.md` は ✅ 10 行 / ❌ 4 行**（Phase 3 と同一）。**⚠️ 判定不能が 1 行も無いこと**
- ❌ の 4 行は `L1-06-web-imports-api` / `L2-01-phantom-package` / `L2-05-sql-injection` / `L3-03-authz-bypass`（Phase 3 と同じ内訳）
- 「実際に止めた層」の列に `l4-mutation` が現れるケースがあってもよい。**それは退行ではなく観測である**（§1.42 と同じ型: `l4-mutation` は L1 系・L2 系の欠陥でも fail する）。現れたケースを記録し、Task 7 で findings に書く

**⚠️ が出たら、そのケースのログを読んで原因を特定してから先に進む。** ケースや `case.patch` を書き換えて ⚠️ を消してはいけない。

- [ ] **Step 8: `RESULTS.md` をコミットする**

```bash
git add verification/RESULTS.md
git commit -m "chore: run-all.sh の再実行結果を反映（ゲート 9 本での退行なしを確認）"
```

---

## Task 6: L4 系 2 ケースを作り、判定と対照フル実行を記録する

**Files:**
- Create: `verification/cases/L4-01-empty-assertion/case.patch`
- Create: `verification/cases/L4-01-empty-assertion/expect.yml`
- Create: `verification/cases/L4-02-off-by-one-fixed-by-test/case.patch`
- Create: `verification/cases/L4-02-off-by-one-fixed-by-test/expect.yml`

**Interfaces:**
- Consumes: `GATE_ORDER` に `l4-mutation` が入り閾値が決まった状態（Task 4）、依存スキップを持つ `run-case.sh`（Task 5）
- Produces: 2 ケースの `claimVerdict` / `claimGateVerdict` と、各ケースに対する**フル実行（差分限定なし）のスコアと生き残り mutant 一覧**

**`claimed_layer` は手順書 §10 の記述をそのまま写す。** 手順書 §10（手順書 809〜810 行）は次のように書いている。

| 落とし穴（手順書 §10 の原文） | 手順書が主張する層 |
|---|---|
| アサーションの緩いテストでカバレッジだけ稼ぐ | **L4** |
| 誤った実装をテストで固定化する | **L4 / L5** |

したがって両ケースの `claimed_layer` は `L4`、`claimed_gate` は `l4-mutation` とする。

- [ ] **Step 1: `L4-01-empty-assertion` のパッチを作る**

`apps/api/src/discount/discount.spec.ts` の 6 つの単体テストのアサーションを `toBeDefined()` に緩める。**fast-check のプロパティテストは残す**（残しても mutant は生き残る。境界値を見ていないため）。

```bash
git checkout -b tmp/build-L4-01
```

`apps/api/src/discount/discount.spec.ts` の `describe('applyDiscount', ...)` の中身を次に置き換える。**`MEMBER_DISCOUNT_MIN_PRICE` の import は使い続ける**（未使用になると `l1-lint` / `l1-typecheck` が赤くなり、ケースが「L1 が止めた」に化ける）。

```ts
describe('applyDiscount', () => {
  it('非会員は割引されない', () => {
    expect(applyDiscount(2000, false)).toBeDefined();
  });

  it('会員で閾値ちょうどのときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE, true)).toBeDefined();
  });

  it('会員で閾値のすぐ下のときは割引されない', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE - 1, true)).toBeDefined();
  });

  it('会員で閾値のすぐ上のときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE + 1, true)).toBeDefined();
  });

  it('割引後の端数は切り捨てる', () => {
    expect(applyDiscount(1005, true)).toBeDefined();
  });

  it('0 円は割引されない', () => {
    expect(applyDiscount(0, true)).toBeDefined();
  });
});
```

- [ ] **Step 2: L4-01 が他の層を赤くしないことを確認する**

L4 のケースは「L3 が通るのに L4 だけが止める」ことを示せて初めて意味を持つ（設計書 §9）。パッチを当てた状態で L1〜L3 が緑であることを先に確かめる。

```bash
./scripts/gates/l1-typecheck.sh; echo "l1-typecheck=$?"
./scripts/gates/l1-lint.sh;      echo "l1-lint=$?"
./scripts/gates/l3-test.sh;      echo "l3-test=$?"
```

期待: すべて `0`。`l1-lint` が赤い場合は未使用 import か lint ルール違反が入っている。パッチを直す（**これは「判定を match にするための書き換え」ではない。「L4 以外の層に当たらない欠陥にする」というケース設計の要件である**）。

- [ ] **Step 3: L4-01 の対照フル実行を測る**

差分限定ではなく `apps/api` 全体をミューテートして、**このパッチが本当にミューテーションスコアを下げるのか**を確かめる。ゲートが緑でも「L4 に検出力が無い」のか「手順書の PR 実行方法が見ていない」のかを切り分けるための対照である（決定 2）。

```bash
git add -A && git commit -m "tmp: L4-01 の対照フル実行"
pnpm --filter api exec stryker run 2>&1 | tee /tmp/L4-01-full.log
tail -n 40 /tmp/L4-01-full.log
```

記録すること:
- 全体スコア（**Task 1 Step 7 の baseline スコアとの差**）
- `discount.ts` の生き残り mutant の件数と内容（`reports/mutation/mutation.json` または `clear-text` の出力）
- **閾値（Task 4 で決めた `break`）を割ったか**

- [ ] **Step 4: L4-01 の `case.patch` を書き出す**

```bash
mkdir -p verification/cases/L4-01-empty-assertion
git diff main...HEAD -- apps/api/src/discount/discount.spec.ts \
  > verification/cases/L4-01-empty-assertion/case.patch
git checkout main && git branch -D tmp/build-L4-01
```

`case.patch` に `apps/api/src/discount/discount.spec.ts` の差分だけが入っていることを確認する（`git diff --stat` 相当を目で見る）。

- [ ] **Step 5: L4-01 の `expect.yml` を書く**

```yaml
id: L4-01-empty-assertion
pitfall: アサーションの緩いテストでカバレッジだけ稼ぐ
claimed_layer: L4
# 手順書 §10 は「アサーションの緩いテストでカバレッジだけ稼ぐ」を L4 に割り当て、
# 「ミューテーションスコアで露見させる」と書いている。
claimed_gate: l4-mutation
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: pass
  l3-openapi-drift: pass
  l4-mutation: pass     # ← 実測値を書く（Step 6 で確定させる）
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 6: L4-01 を実行して判定を出す**

```bash
git add verification/cases/L4-01-empty-assertion
git commit -m "test(l4): L4-01-empty-assertion ケースを追加"
./verification/run-case.sh L4-01-empty-assertion 2>&1 | tail -n 30
```

stderr の `l4-mutation exit=N` と、標準出力の JSON（`claimVerdict` / `claimGateVerdict` / `blockedBy`）を記録する。

**予測は `l4-mutation exit=0` → `claimVerdict: not-caught` → ❌ である。** パッチが触るのは spec ファイルだけなので、`stryker-diff.sh` の差分が 0 件になり「変更なし。スキップします。」で exit 0 になる。ログに `L4_MUTATE_FILES=(none)` が出ていることを確認する（これが「何も走っていない緑」の証跡である）。

実測が予測と違ったら**実測を採る**。`expect.yml` の `l4-mutation` を実測値に合わせて更新する（`claimed_layer` / `claimed_gate` は触らない）。

- [ ] **Step 7: `L4-02-off-by-one-fixed-by-test` のパッチを作る**

実装の境界条件を off-by-one にし、**テストもその誤った値に合わせる**。

```bash
git checkout -b tmp/build-L4-02
```

`apps/api/src/discount/discount.ts`:

```ts
  if (price <= MEMBER_DISCOUNT_MIN_PRICE) {
    return price;
  }
```

（`<` を `<=` にする。閾値ちょうど = 1000 円が割引されなくなる）

`apps/api/src/discount/discount.spec.ts` の該当テストを、その誤った挙動に合わせる:

```ts
  it('会員で閾値ちょうどのときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE, true)).toBe(1000);
  });
```

- [ ] **Step 8: L4-02 が他の層を赤くしないことを確認する**

```bash
./scripts/gates/l1-typecheck.sh; echo "l1-typecheck=$?"
./scripts/gates/l1-lint.sh;      echo "l1-lint=$?"
./scripts/gates/l3-test.sh;      echo "l3-test=$?"
```

期待: すべて `0`。`l3-test` には統合テストと e2e も含まれるが、シードの価格は 1200 / 600 / 5000 円で 1000 円の境界に当たらないため緑のままになる見込み。**赤くなったらどのテストが落ちたかを確認し、境界に当たらない形にパッチを調整する**（ケース設計の要件。Step 2 と同じ）。

- [ ] **Step 9: L4-02 の対照フル実行を測る**

```bash
git add -A && git commit -m "tmp: L4-02 の対照フル実行"
pnpm --filter api exec stryker run 2>&1 | tee /tmp/L4-02-full.log
tail -n 40 /tmp/L4-02-full.log
```

記録すること: Step 3 と同じ項目。特に **`discount.ts` の生き残り mutant が baseline（Task 1）から増えたか**。増えていなければ「テストが実装に追従しているので mutant は殺され、スコアは動かない」＝**L4 は一貫して間違った仕様を検出しない**という結論の実測データになる。

- [ ] **Step 10: L4-02 の `case.patch` と `expect.yml` を書く**

```bash
mkdir -p verification/cases/L4-02-off-by-one-fixed-by-test
git diff main...HEAD -- apps/api/src/discount/ \
  > verification/cases/L4-02-off-by-one-fixed-by-test/case.patch
git checkout main && git branch -D tmp/build-L4-02
```

```yaml
id: L4-02-off-by-one-fixed-by-test
pitfall: 誤った実装をテストで固定化する
claimed_layer: L4
# 手順書 §10 は「誤った実装をテストで固定化する」を L4 / L5 に割り当て、
# 「ミューテーションテスト＋別観点からのレビュー」を対策として挙げている。
# L5 は Phase 5 の対象なので、本ケースは L4 の側だけを測る。
claimed_gate: l4-mutation
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: pass
  l3-openapi-drift: pass
  l4-mutation: pass     # ← 実測値を書く（Step 11 で確定させる）
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 11: L4-02 を実行して判定を出す**

```bash
git add verification/cases/L4-02-off-by-one-fixed-by-test
git commit -m "test(l4): L4-02-off-by-one-fixed-by-test ケースを追加"
./verification/run-case.sh L4-02-off-by-one-fixed-by-test 2>&1 | tail -n 30
```

このケースは `discount.ts` を触るので、**差分限定の Stryker が実際に走る**（`L4_MUTATE_FILES=src/discount/discount.ts` が出ることを確認する）。

**`l4-mutation` が fail(1) を返した場合は、その理由を必ず切り分ける。**

- `reports/mutation/mutation.json`（または `clear-text` 出力）の生き残り mutant を読み、**off-by-one に関係する mutant（`<=` の境界）が生き残ったのか**、それとも**`discount.ts` 単体のスコアがフル実行から決めた閾値を下回っただけ**なのかを判定する
- 後者なら、`RESULTS.md` の ✅ は「L4 が off-by-one を捕まえた」ことを意味しない。`L2-05` と同じ**副作用による検出**（§1.40）であり、その旨を findings に明記する

- [ ] **Step 12: コミットする**

```bash
git status --porcelain          # 一時ブランチの残骸が無いこと
git add verification/cases/L4-01-empty-assertion verification/cases/L4-02-off-by-one-fixed-by-test
git commit -m "test(l4): L4 系 2 ケースの期待値を実測に合わせた"
```

---

## Task 7: 全 16 ケースを回し、findings と CLAUDE.md を更新する

**Files:**
- Modify: `verification/RESULTS.md`（`run-all.sh` の生成物）
- Modify: `docs/superpowers/phase0-findings.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Task 1〜6 のすべての実測値
- Produces: 16 ケース分の `RESULTS.md`、仮説 4 の結論、Phase 5 への申し送り

- [ ] **Step 1: `run-all.sh` を回す（バックグラウンド）**

```bash
./verification/run-all.sh > /tmp/run-all-task7.log 2>&1
```

**必ずバックグラウンドで実行する。**

- [ ] **Step 2: 結果を確認する**

```bash
grep -E '^\|' verification/RESULTS.md | tail -n 20
grep -c '✅' verification/RESULTS.md; grep -c '❌' verification/RESULTS.md
grep -E '判定不能' verification/RESULTS.md; echo "inconclusive_grep=$?"
grep -E '^(--- |全体の所要時間)' /tmp/run-all-task7.log
```

期待:
- 16 行（既存 14 + L4 系 2）
- **⚠️ 判定不能が 0 行**
- 既存 14 ケースの判定が Task 5 Step 7 と同一

判定が変わったケースがあれば、その原因（`l4-mutation` が新たに fail したのか、閾値の変更が効いたのか）を特定してから次へ進む。

- [ ] **Step 3: `phase0-findings.md` の §1 に発見を追記する**

`§1.45` から連番で追加する（現在の最後は §1.44）。**Task 1〜6 で実測したものだけを書く。推測を書かない。** 少なくとも次の項目を、実測値・ログの文字列・再現手順とともに書く。

**`§1.45` は仮説 4（`scripts/stryker-diff.sh` のパスのずれ）の結論に割り当てること。** Task 3 が作った `scripts/stryker-diff.sh` のコメントが `§1.45` を名指しで参照しているので、別の発見をこの番号に置くとコード内の参照が壊れる。

| 書くべき発見 | 根拠になる実測 |
|---|---|
| **仮説 4 の結論**（`stryker-diff.sh` のパスのずれ）。空振りするのか、しないのか。`git diff` が返したパスと `--mutate` に渡った値をそのまま引用する | Task 3 Step 2 |
| **手順書 §5.3 の pathspec `'apps/api/src/**/*.ts'` は `src` 直下のファイルに一致しない**（§1.23 と同型） | Task 3 Step 3 |
| **手順書 §5.3 の差分限定スクリプトは、spec ファイルだけの変更に原理的に無反応である。** L4 が最も得意な「空虚なテスト」を PR ゲートでは一切見ない | Task 6 Step 6 + Step 3 の対照フル実行 |
| **手順書 §5.2 の Jest 設定は、テストランナーが Testcontainers を使う構成との相互作用に触れていない**（申し送り #28 の結論） | Task 1 Step 5 |
| **`break: null` で実測したスコアと、手順書が推奨する `break: 60` の距離** | Task 1 Step 7 / Task 2 Step 5 / Task 4 Step 2 |
| **フル実行から決めた閾値を差分実行に当てると意味が変質する。** 変更ファイルが平均より弱いだけで落ちる（実際に落ちたケースがあれば、そのケース名と単体スコア） | Task 5 Step 4 / Task 6 Step 11 |
| **手順書 §5.2 の web 設定の実測**（`related` オプションの有無、`.d.ts` が `mutate` に入る問題、vitest 4 との噛み合わせ） | Task 2 Step 3 |
| **`l4-mutation` は L1 系・L2 系の欠陥でも fail する**（該当ケースがあれば。§1.42 の型が L4 にも及ぶこと） | Task 5 Step 7 |
| **Stryker は初回テスト実行が緑でないと動かないため、L3 が赤いケースでは L4 は原理的に判定できない。** ハーネスに依存スキップを入れた理由と、入れなかった場合に何が起きるか（5 ケースが ⚠️） | Task 4 Step 5 / Task 5 Step 1 |
| **依存追加が既存ゲートに与えた影響**（`l2-osv` が赤くなったか、`minimumReleaseAge` に阻まれたか。何も起きなかった場合も「起きなかった」と書く） | Task 1 Step 8 / Task 2 Step 6 |
| **`trustPolicy: no-downgrade` は依存追加を全面的・恒久的にブロックした**（§1.21 の `minimumReleaseAge`、§1.39 の OSV との衝突に続く 3 例目）。`semver@6.3.1` が attestation を持たず 6.x の上位版も無いため、babel を持つこのリポジトリでは Stryker に限らず**どの依存も追加できなかった**。`pnpm install --frozen-lockfile`（`l2-install`）は lockfile を再解決しないので緑のままで、**ゲートが緑でも依存追加が不可能**という状態が成立していた。人間の判断で `trustPolicyIgnoreAfter: 43200`（30 日）を入れて解消した。手順書 §3.3 が pnpm 側の供給網設定に触れていない問題の 3 例目として記録する | Task 1 の 1 回目の派遣（BLOCKED）と `pnpm-workspace.yaml` のコミット |

`§1.13`（「ゲートが緑」と「ゲートが守っている」は別物である）の観測回数を更新する。Phase 4 で踏んだ件数を数え、表に追記する。**踏まなかったなら「踏まなかった」と書く**（回数を盛らない）。

- [ ] **Step 4: `phase0-findings.md` の §3 を更新する**

`### Phase 4（L4）` の表を Phase 3 と同じ体裁で「対応状況」列付きに書き換える。申し送り #13 / #14 / #15 / #27 / #28 / #29 / #30 / #31 / #32 の各行に、**解消 / 一部解消 / 未解決 / 対象外と決定** のいずれかを実測とともに書く。

続けて `### Phase 5（L5）` を新設し、Phase 4 の実測から生じた申し送りを書く。少なくとも次を含める。

- **申し送り #27（ルール ID 照合）は Phase 4 でも未解決なら持ち越す。** `l4-mutation` が加わって穴が広がったかどうか（どの mutant が生き残って落ちたかを判定に伝えていない）
- **`L5-02-n-plus-one` の前提**（§2.2）。Phase 5 で (a) / (b) のどちらを選ぶか。L4 の 2 ケースで得た「L3 も一緒に赤になるならそのケースは価値を証明していない」の実測が判断材料になる
- **`cloudbuild.pr.yaml` に L4 のステップを書くときの注意。** 手順書 §7 の `l4-mutation` ステップは `corepack enable && ./scripts/stryker-diff.sh` を実行するが、このリポジトリはローカルで `corepack` を使わない。また `git fetch --depth=50` を外した（Task 3 Step 5）ので、CI では `GATE_BASE_REF` を渡す必要がある
- **nightly のフル実行**（手順書 §5.4）。Phase 4 では対照として手で回したが、`cloudbuild.nightly.yaml` に載せるときの形。`incremental` を切ったので「incremental の誤差をリセットする」という §5.4 の動機自体がこのリポジトリでは成立しない
- **`run-all.sh` の所要時間**（申し送り #26）。ゲートが 9 本・ケースが 16 本になった実測を記録し、高速化の要否は Phase 5 で判断する（決定 4 で本フェーズでは扱わないと決めた）

- [ ] **Step 5: `phase0-findings.md` の §4 に受け入れ確認記録を追加する**

`### Phase 4（L4 + L4 系 2 ケース）` を Phase 3 と同じ体裁で追加する。

| 項目 | 記録する内容 |
|---|---|
| `./scripts/gates/gates.test.sh` | exit code と成功件数（Phase 3 は **35 件**） |
| `node --test verification/lib/judge.test.mjs` | exit code と成功件数（Phase 3 は **26 件**）。**`judge.mjs` を変更していないので件数は変わらない見込みだが、実行して確認する** |
| `shellcheck scripts/gates/*.sh scripts/stryker-diff.sh verification/*.sh` | exit code と指摘件数 |
| `pnpm turbo build typecheck test` | exit code とタスク数・テスト件数 |
| `pnpm exec eslint . --max-warnings=0` | exit code |
| api / web のフル実行ミューテーションスコア | 実測値（`break: null` 時点）と、決めた `break` |
| `./verification/run-all.sh` | 16 ケースの判定内訳（✅ / ❌ / ⚠️ の行数）と所要時間（**スコープを明示**） |
| 既存 14 ケースの退行 | あり / なし。あった場合はケース名と原因 |
| 仮説 4 | 結論を書いた §1.NN への参照 |

**L4 系 2 ケースの表**も Phase 3 と同じ体裁で追加する（ケース / 落とし穴 / 手順書の主張 / 止めたゲート / 判定）。

- [ ] **Step 6: `CLAUDE.md` を更新する**

変更する箇所は次の 4 つ。**それ以外は触らない。**

1. **「現在地」**: Phase 4 完了、次は Phase 5。ブロックするゲートは 9 本（+ 非ブロック 1 本）、ケースは 16 本、`RESULTS.md` の内訳（✅ / ❌ の行数）
2. **環境の表**: `l4-mutation` は Docker を必要としないことを明記（Docker 必須のゲート一覧に混ぜない）
3. **「この検証で繰り返し出た教訓」**: Phase 4 で「緑と守っているは別物」を踏んだ回数を反映（§1.13 の更新と整合させる）。**Phase 4 の新しい教訓があれば 1 段落だけ足す**（例: L4 は L3 の後段でしか動けないという層の順序依存）
4. **「`RESULTS.md` の ❌ を読むときの注意」**: L4 系の ❌ が出た場合、それが何の反証データなのかを 1 項目として足す

`./verification/run-case.sh <CASE-ID>` の所要時間の記述は、**実測していないなら触らない**（§1.38 の規律）。

- [ ] **Step 7: 最終確認を回す**

```bash
./scripts/gates/gates.test.sh;                          echo "gates.test=$?"
node --test verification/lib/judge.test.mjs 2>&1 | tail -n 5
shellcheck scripts/gates/*.sh scripts/stryker-diff.sh verification/*.sh; echo "shellcheck=$?"
pnpm turbo build typecheck test 2>&1 | tail -n 10
pnpm exec eslint . --max-warnings=0;                    echo "eslint=$?"
git status --porcelain
git branch --list 'verify/*'
```

期待: すべて exit 0、作業ツリーがクリーン（`RESULTS.md` のコミット後）、`verify/*` ブランチが残っていない。

- [ ] **Step 8: コミットする**

```bash
git add verification/RESULTS.md docs/superpowers/phase0-findings.md CLAUDE.md
git commit -m "docs: Phase 4（L4）の実測結果・findings・CLAUDE.md を反映"
```

---

## Self-Review（計画作成時に実施した確認）

**1. 仕様（設計書 §10 の Phase 4 行 + 手順書 §5）の網羅**

| 要求 | 対応タスク |
|---|---|
| Stryker の導入（api = jest-runner、web = vitest-runner。手順書 §5.1） | Task 1 / Task 2 |
| `stryker.config.json`（手順書 §5.2） | Task 1 Step 6 / Task 2 Step 2 |
| PR は差分のみ（手順書 §5.3） | Task 3 |
| incremental の注意点（手順書 §5.4） | 逸脱表 + Task 7 Step 4（nightly の申し送り） |
| 閾値の決め方（手順書 §5.5。`break: null` → 実測 → 少し下） | Task 1 Step 7 / Task 2 Step 5 / Task 4 Step 2 |
| `l4-mutation` をブロッキングゲートに（手順書 §7 / 設計書 §6） | Task 4 Step 3 |
| L4 系 2 ケースの判定完了（設計書 §9） | Task 6 |
| 仮説 4 に結論（設計書 §7） | Task 3 Step 2〜3 + Task 7 Step 3 |
| 実測スコアの把握 → 閾値設定 → ケース判定 の順序（設計書 §10） | Task 1/2 → Task 4 → Task 6 の順で固定 |
| 申し送り #13（turbo 経由 / `generate` の先行） | Task 1 Step 7、Task 3 Step 5 のコメント |
| 申し送り #14（`toOrderResponse` は除外しない） | Task 1 Step 6 |
| 申し送り #15（web の `afterEach(cleanup)`） | 既に実装済み。Task 2 Step 5 で web の mutant 生存を見るときの前提 |
| 申し送り #28（unit だけを走らせる） | Task 1 Step 2〜5 |
| 申し送り #29（`mutate` の除外候補） | Task 1 Step 6 / Task 2 Step 4 |
| 申し送り #30（`GATE_ORDER` は 1 箇所） | Task 4 Step 3 |
| 申し送り #31（依存追加が別の層を赤くする） | Task 1 Step 8 / Task 2 Step 6 + Global Constraints |
| 申し送り #32（turbo 経由 / `--filter='...[origin/main]'` を使わない） | Task 3 Step 5（`GATE_BASE_REF` で明示的に比較対象を渡す） |
| 申し送り #27（ルール ID 照合） | **本フェーズでは対象外。** Task 7 Step 4 で Phase 5 へ持ち越す |
| 申し送り #26（所要時間の高速化） | **決定 4 により本フェーズでは扱わない。** Task 7 Step 4 で Phase 5 へ持ち越す |

**2. プレースホルダの走査**

`Task 4 Step 1` の `gate_fail_if_matches "$_log" 'PLACEHOLDER_実測した文字列に置き換える'` は意図的に残している。Stryker が閾値割れのときに出す文字列を**推測で書かせない**ためで、Step 4 が実測した文字列に置き換えることを明示している。それ以外の「実測値を書く」箇所（`expect.yml` の `l4-mutation`、`thresholds.break`）はすべて、どの Step の実測から決めるかを名指ししている。

**3. 型と名前の整合**

- `unitProject`（Task 1 Step 2 で export、Step 3 で import）— 名前は一致している
- `apps/api/jest.stryker.config.ts` — Task 1 Step 3 で作成、Step 5 で `-c` に渡し、Step 6 の `jest.configFile` が参照する。3 箇所で同じパス
- `L4_MUTATE_FILES=` — Task 3 Step 5 で出力、Task 6 Step 6 / Step 11 で確認する
- `GATE_BASE_REF` — `l2-new-deps.sh` の既存の規約と同名。`run-case.sh:168` が既に export している
- `scripts/stryker-diff.sh` の `exit 3` — Task 3 Step 5 で導入し、Task 4 Step 1 のコメントが error(2) に写像されることを説明している
