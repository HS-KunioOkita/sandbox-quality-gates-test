# 多層品質ゲート L1〜L5 検証環境 設計書

**作成日**: 2026-07-29
**対象**: `docs/多層品質ゲート_L1-L5_導入手順_NestJS-React.md`（以下「手順書」）

---

## 1. 目的

手順書に従って NestJS + React モノレポに L1〜L5 の品質ゲートを構築し、**それが手順書の主張どおりに機能するかを検証する**。

検証したい問いは 2 つある。

1. **各ゲートは、手順書が「この層で止まる」と主張する欠陥を実際に止めるか。**
2. **手順書の記述は、そのまま実行できるか。** 記述漏れ・バージョン差異・コマンドの誤りがあれば特定し、修正提案としてまとめる。

本プロジェクトの成果物は、動作するゲート環境そのものと、`verification/RESULTS.md`（検証結果マトリクス）、および手順書への修正提案である。

### 非目標

- 本番運用可能なアプリケーションを作ること。サンプルアプリはゲート検証の土台であり、それ以上の作り込みはしない。
- Cloud Build 上での実行。ローカル環境に `gcloud` が無く、GCP プロジェクトも用意しない。`cloudbuild.pr.yaml` / `cloudbuild.nightly.yaml` は成果物として作成するが実行しない。
- 認証機構の実装。認可の検証が目的なので、認証は `x-user-id` ヘッダを読むだけの最小実装にする。

---

## 2. 前提環境

| 項目 | 実測値 | 備考 |
|---|---|---|
| Node | v24.11.1 | 手順書は `node:22` イメージ想定 |
| pnpm | 11.1.1（グローバル） | `corepack` は未インストール |
| Docker | 28.5.1 | Testcontainers / Semgrep / OSV-Scanner / gitleaks をコンテナ実行 |
| gcloud | 未インストール | Cloud Build 実行不可 |
| semgrep / osv-scanner / gitleaks | 未インストール | Docker 経由で実行する |

ローカル実行時は `corepack enable` を使わず、グローバルの pnpm を直接使う。`cloudbuild.*.yaml` 側は `node:22` イメージに corepack が同梱されているため、手順書どおり `corepack enable` を残す。

---

## 3. 全体アプローチ

### 3.1 構築と検証の刻み方

手順書 §9 のロードマップと同じ順序で層ごとに構築し、**各層を入れた直後にその層の検証ケースを回す**。これにより層ごとの検知能力を切り分けて評価でき、手順書の記述とのズレも層単位で記録できる。

全ゲートを一括構築して最後にまとめて検証する方式は採らない。詰まり（ESLint の型情報付きルールと tsconfig の整合、Stryker × Vitest の噛み合わせなど）が終盤に集中し、どの層が何を捕まえたかの切り分けも甘くなるため。

### 3.2 欠陥ケースの管理方式

欠陥コードをリポジトリに常設すると**ゲートが常時赤になり以後の作業が止まる**。そのため、欠陥は **パッチファイル + 自動適用ハーネス**で管理する。

- 各ケースは `verification/cases/<CASE-ID>/case.patch` として差分の形で保存する。
- `verification/run-case.sh` が一時ブランチを切ってパッチを適用し、ゲートを実行して結果を記録し、ブランチを捨てる。

**一時ブランチを切ることが本質である。** 以下のゲートは「ベースブランチとの差分」を見るため、ブランチを切らないと検証不可能である。

- L4 `scripts/stryker-diff.sh`（変更ファイルのみミューテート）
- L2 新規依存検出（`git diff ... -- '**/package.json'`）
- L1 差分 lint（手順書 §2.6 の既存コード凍結方式）

欠陥ケースをゲート対象外の隔離ディレクトリに常設する方式は採らない。「ゲート対象外」に置く以上、lint 設定や tsconfig の include を歪めることになり、**検証対象であるゲート設定そのものに手を入れてしまう**ため。

### 3.3 ゲートスクリプトの切り出し

手順書のゲートは `cloudbuild.pr.yaml` のステップ内にインラインで書かれている。これをローカルで実行するにはシェル片のコピペになる。

ゲート本体を `scripts/gates/<gate-id>.sh` に切り出し、**`cloudbuild.pr.yaml` とローカル検証ハーネスの両方が同じスクリプトを呼ぶ**構成にする。「ローカルで検証したものと CI で動くものが同一」であることが担保される。これは手順書の構成から意図的に離れる部分であり、手順書への改善提案の一つとして扱う。

---

## 4. リポジトリ構成

手順書 §1.1 に準拠し、`verification/` と `scripts/gates/` を追加する。

```
.
├── apps/
│   ├── api/                                # NestJS
│   │   ├── prisma/schema.prisma
│   │   ├── src/
│   │   │   ├── discount/                   # applyDiscount 純関数
│   │   │   ├── orders/                     # Controller / Service
│   │   │   ├── auth/                       # AuthGuard
│   │   │   ├── app.module.ts
│   │   │   ├── main.ts
│   │   │   └── generate-openapi.ts
│   │   ├── test/
│   │   │   ├── setup-db.ts                 # Testcontainers
│   │   │   ├── orders.int-spec.ts
│   │   │   └── orders.e2e-spec.ts
│   │   ├── eslint.config.js
│   │   ├── jest.config.ts
│   │   ├── stryker.config.json
│   │   └── tsconfig.json
│   └── web/                                # React + Vite
│       ├── src/
│       │   ├── api/
│       │   │   ├── schema.d.ts             # openapi-typescript 生成物
│       │   │   └── client.ts
│       │   ├── features/orders/
│       │   │   ├── OrderList.tsx
│       │   │   └── orderTotal.ts
│       │   └── test/setup.ts
│       ├── e2e/orders.spec.ts               # Playwright
│       ├── eslint.config.js
│       ├── playwright.config.ts
│       ├── stryker.config.json
│       ├── vitest.config.ts
│       └── tsconfig.json
├── packages/
│   ├── shared/                             # 共有型
│   ├── eslint-config/index.js
│   └── tsconfig/base.json
├── .claude/skills/code-review/SKILL.md     # L5 レビュー観点
├── .semgrep/nestjs.yml                     # L2 カスタムルール
├── scripts/
│   ├── gates/
│   │   ├── l2-install.sh
│   │   ├── l1-typecheck.sh
│   │   ├── l1-lint.sh
│   │   ├── l2-semgrep.sh
│   │   ├── l2-osv.sh
│   │   ├── l2-gitleaks.sh
│   │   ├── l2-new-deps.sh
│   │   ├── l3-test.sh
│   │   ├── l3-openapi-drift.sh
│   │   ├── l4-mutation.sh
│   │   └── l5-ai-review.sh
│   └── stryker-diff.sh
├── verification/
│   ├── cases/<CASE-ID>/{case.patch, expect.yml}
│   ├── reviews/<CASE-ID>.md                # L5 の出力（目視判定用）
│   ├── run-case.sh
│   ├── run-all.sh
│   └── RESULTS.md
├── cloudbuild.pr.yaml
├── cloudbuild.nightly.yaml
├── eslint.config.js                        # ルート（手順書に記述が無い）
├── pnpm-workspace.yaml
├── turbo.json
└── package.json
```

---

## 5. サンプルアプリ

**題材**: 会員割引付きの注文管理。エンティティは `User` と `Order` の 2 つ。

### 5.1 API 側

| ファイル | 役割 | 主に効かせるゲート |
|---|---|---|
| `discount/discount.ts` | `applyDiscount(price, isMember)` 純関数 | L4 ミューテーション、fast-check PBT |
| `orders/orders.controller.ts` | `@UseGuards(AuthGuard)` + `GET/POST /orders` | L2 Semgrep カスタムルール、L5 |
| `orders/orders.service.ts` | Prisma で Order を読み書きし割引を適用 | L3 統合、L4、L5（N+1） |
| `auth/auth.guard.ts` | `x-user-id` ヘッダによる簡易認証 | L2 / L5 |

`User` テーブルを置く理由は 2 つある。認可（他ユーザーの注文が見えないこと）の検証と、N+1 クエリの検証である。

テストは 4 層に配置する。

| 種別 | ファイル | ツール |
|---|---|---|
| ユニット | `src/discount/discount.spec.ts` | Jest + fast-check |
| ユニット | `src/orders/orders.service.spec.ts` | Jest（Prisma モック） |
| 統合 | `test/orders.int-spec.ts` | Jest + Testcontainers（実 PostgreSQL） |
| E2E | `test/orders.e2e-spec.ts` | Jest + supertest（403 の確認を含む） |

### 5.2 Web 側

`features/orders/OrderList.tsx`（注文一覧 1 画面）と `features/orders/orderTotal.ts`（合計・割引表示のロジック）。

**ロジックを `.tsx` から切り出す**のは、Stryker の Vitest ランナーがミューテートしやすい純ロジックを確保するためである。

API 型は `openapi-typescript` の生成物 `src/api/schema.d.ts` を経由して消費する。`packages/shared` は「Web から API 内部実装を直 import させない」ルール（手順書 §2.4）の検証に必要なため用意する。

### 5.3 落とし穴カバレッジ

手順書 §10 の 7 項目すべてに欠陥ケースを仕込める。

| 手順書 §10 の落とし穴 | 仕込む先 |
|---|---|
| lint を `eslint-disable` で黙らせる | `orders.service.ts` |
| `any` で型チェックを回避 | `api/client.ts`（Web） |
| 存在しないパッケージを import | `apps/api/package.json` |
| 認可チェックの欠落 | `orders.controller.ts` の `@UseGuards` を外す |
| アサーションの緩いテストでカバレッジを稼ぐ | `discount.spec.ts` |
| 誤った実装をテストで固定化 | `applyDiscount` の境界値を off-by-one に |
| 設計の一貫性が崩れ重複が増える | `orderTotal.ts` に割引ロジックを二重実装 |

---

## 6. ゲートのローカル実行

`scripts/gates/` に 1 ゲート = 1 スクリプトで切り出す。

| スクリプト | 中身 | ブロック | 手順書からの読み替え |
|---|---|---|---|
| `l2-install.sh` | `pnpm install --frozen-lockfile --ignore-scripts` + `prisma generate` | ● | 手順書 §3.3 ①。ゲートとして扱う（後述） |
| `l1-typecheck.sh` | `pnpm turbo typecheck` | ● | `corepack enable` を外す |
| `l1-lint.sh` | `pnpm eslint . --max-warnings=0` | ● | — |
| `l2-semgrep.sh` | Docker で `semgrep scan --config=...` | ● | `semgrep ci` → `semgrep scan` |
| `l2-osv.sh` | Docker で `osv-scanner` | ● | v1/v2 で CLI 書式が異なる |
| `l2-gitleaks.sh` | Docker で `gitleaks detect --no-git --redact` | ● | — |
| `l2-new-deps.sh` | `git diff` で package.json の追加行を検出 | ○ | 手順書は警告のみで exit 0 |
| `l3-test.sh` | `pnpm turbo test --filter=...` | ● | — |
| `l3-openapi-drift.sh` | 生成 → `git diff --exit-code` | ● | — |
| `l4-mutation.sh` | `scripts/stryker-diff.sh` を呼ぶ | ● | — |
| `l5-ai-review.sh` | `claude -p "/code-review ..."` | ○ | API キー不要（サブスクリプション認証） |

`l2-install.sh` をゲートとして扱う理由は 2 つある。手順書 §3.3 ① の `--frozen-lockfile` が架空パッケージに対する実質的な防御線であり（仮説 3）、かつ `--ignore-scripts` と `prisma generate` の併用問題（仮説 2）がここで顕在化するため。ハーネスは他のゲートより先にこれを実行し、失敗した場合は後続ゲートを実行せず「install で止まった」と記録する。

### 6.1 exit code の正規化

**Docker が起動していないだけなのに「ゲートが欠陥を検出した」と記録される**のが、このハーネス最大の誤判定リスクである。各ゲートスクリプトで exit code を 3 値に正規化する。

| code | 意味 | `RESULTS.md` での扱い |
|---|---|---|
| `0` | pass（ゲート通過） | 判定に使う |
| `1` | fail（ゲートがブロック＝欠陥を検出） | 判定に使う |
| `2` | error（ツールが実行できなかった） | **判定不能として記録し、ケース全体を無効化** |

各ツールの生 exit code は多様（Semgrep は 1=findings / 2=error、ESLint は 1=lint error / 2=config error）なので、スクリプト側で明示的にマッピングする。`run-case.sh` は `2` を検出したら「判定できなかった」と記録し、緑/赤の推論をしない。

---

## 7. 検証で確かめるべき「手順書とのズレ」仮説

構築中に当たると見込んでいる箇所。**これ自体が検証の主目的である。** 各項目に結論を出すことが Phase 6 の完了条件となる。

| # | 仮説 | 影響 |
|---|---|---|
| 1 | `semgrep ci` は Semgrep AppSec Platform（トークン）前提であり、自前 CI では `semgrep scan` が正しい | 手順書 §3.2 / §7 のコマンドが動かない |
| 2 | `pnpm install --ignore-scripts` は Prisma の `prisma generate` を止めるため、明示的な生成ステップが必要 | 手順書 §3.3 と Prisma の併用手順が欠落 |
| 3 | 「存在しないパッケージ」を OSV-Scanner は検出しない（脆弱性 DB 照合であり架空パッケージは対象外）。実際に止めるのは `--frozen-lockfile` と L1 typecheck | 手順書 §10 の対応表が要修正 |
| 4 | `scripts/stryker-diff.sh` はパスのずれで空振りする。`git diff` はリポジトリルート相対を返すが `pnpm --filter api exec` は `apps/api` をカレントにする | 手順書 §5.3 のスクリプトが機能しない |
| 5 | Semgrep カスタムルール `nest-controller-without-guard` がデコレータに対する `pattern-not` で期待通り動くか不明 | 手順書が唯一「自社で書け」と言う部分の実現可能性 |
| 6 | ルートと `apps/api` の `eslint.config.js` が手順書に無い。`pnpm eslint .` をルートで回すにはルートのフラットコンフィグが必要 | 手順書 §2.4 の記述漏れ |
| 7 | `reportUnusedDisableDirectives` と `eslint-comments/no-unused-disable` は機能重複し二重報告になる可能性 | 手順書 §2.4 の設定が冗長 |
| 8 | Testcontainers 起動後の Prisma マイグレーション適用が手順書に無い。`DATABASE_URL` 差し替えだけでは空の DB | 手順書 §4.2 の記述漏れ |

---

## 8. 検証ハーネス

### 8.1 ケースの構造

```
verification/cases/L1-02-explicit-any/
├── case.patch     # 欠陥を注入する差分
└── expect.yml     # 期待結果（機械可読）
```

```yaml
# expect.yml
id: L1-02-explicit-any
pitfall: any で型チェックを回避する          # 手順書 §10 の落とし穴
claimed_layer: L1                            # 手順書が「この層で止まる」と主張

# ブロックするゲート：pass / fail を期待値として書く
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: fail        # ← ここで止まるべき
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: pass
  l3-openapi-drift: pass
  l4-mutation: pass

# 非ブロックゲート：exit code ではなく「指摘したか」を期待値として書く
expect_detection:
  l2-new-deps: false
  l5-ai-review: false
```

**非ブロックゲート（`l2-new-deps` と `l5-ai-review`）は exit code が常に 0 なので、`expect` ではなく `expect_detection` に分ける。** 判定材料は exit code ではなく出力内容である。

- `l2-new-deps` は出力に `NEW_DEPENDENCY_DETECTED` を含むかで自動判定できる。
- `l5-ai-review` は LLM 出力なので自動判定しない。出力を `verification/reviews/<CASE-ID>.md` に保存し、目視で判定して手動で `RESULTS.md` に追記する。自動判定にすると LLM 出力の文字列マッチという脆い仕組みを作ることになるため、意図的に手動とする。

### 8.2 `run-case.sh` の動作

```
1. 作業ツリーがクリーンか確認（汚れていたら即中断）
2. 検証ブランチの残存を確認（あれば復旧手順を出して中断）
3. main から verify/<CASE-ID> ブランチを切る
4. case.patch を適用してコミット（適用失敗なら即中断）
5. l2-install.sh を実行。失敗したら後続ゲートは実行せず「install で止まった」と記録
6. 残りの scripts/gates/*.sh を順に実行し、exit code と出力を /tmp に記録
7. main に戻り、検証ブランチを削除
8. /tmp の記録を expect.yml と突き合わせ、RESULTS.md に追記
9. l5-ai-review の出力を verification/reviews/<CASE-ID>.md に保存（目視判定用）
```

`l2-install.sh` を最初に実行するのは、依存が入っていなければ他のゲートがそもそも動かないためである。install が失敗した場合に後続を実行しないのは、「依存が無いことによる連鎖失敗」を「ゲートが欠陥を検出した」と誤記録しないため。

**結果は `/tmp` に書いてから main に戻って `RESULTS.md` へ反映する。** 検証ブランチ上で `RESULTS.md` を書くとブランチ削除で消えるため。

`run-all.sh` は全ケースを順に `run-case.sh` に流す。

### 8.3 失敗モードと扱い

| 失敗モード | 扱い |
|---|---|
| パッチが当たらない（アプリコードが変わった） | 即中断。`case.patch` の更新が必要であることを明示 |
| 作業ツリーが汚れている | 実行前に中断。ユーザーの未コミット変更を巻き込まないため |
| 検証ブランチが残存 | 前回の異常終了。復旧手順を出して中断 |
| ゲートが exit code 2 を返した | 判定不能として記録し、ケースを無効化 |

### 8.4 `RESULTS.md` の形

```markdown
| ケース | 落とし穴 | 手順書の主張 | 実際に止めた層 | 判定 |
|---|---|---|---|---|
| L1-02 | any で回避 | L1 | l1-lint | ✅ 一致 |
| L2-01 | 架空パッケージ | L2 (OSV-Scanner) | l2-install | ❌ OSV は無反応 |
```

**「手順書の主張」と「実際に止めた層」を並べる**のがこの表の眼目である。一致すれば手順書が正しく、ズレれば手順書への修正提案になる。単に「ゲートが赤くなった」ではなく「主張どおりの層が捕まえたか」を判定する。

---

## 9. 検証ケース一覧（19 ケース）

### L1（6 ケース）

| ID | 仕込む欠陥 | 期待して止まるゲート |
|---|---|---|
| `L1-01-eslint-disable-abuse` | `/* eslint-disable */` でファイル全体を黙らせる | l1-lint（`no-unlimited-disable`） |
| `L1-02-explicit-any` | `any` で型を回避 | l1-lint（`no-explicit-any`） |
| `L1-03-floating-promise` | `await` 忘れ | l1-lint（`no-floating-promises`） |
| `L1-04-unused-disable` | 効いていない `eslint-disable` を残す | l1-lint（重複報告の有無も確認＝仮説 7） |
| `L1-05-unchecked-index` | 配列添字アクセスの `undefined` 未考慮 | l1-typecheck（`noUncheckedIndexedAccess`） |
| `L1-06-web-imports-api` | Web から `apps/api/src` を直 import | l1-lint（`no-restricted-imports`） |

### L2（5 ケース）

| ID | 仕込む欠陥 | 期待して止まるゲート |
|---|---|---|
| `L2-01-phantom-package` | 存在しないパッケージを import + package.json に追加 | 仮説 3 の検証：何が実際に止めるか |
| `L2-02-guard-missing` | Controller から `@UseGuards` を外す | l2-semgrep（カスタムルール＝仮説 5） |
| `L2-03-hardcoded-secret` | API キーらしき文字列をハードコード | l2-gitleaks / l2-semgrep（`p/secrets`） |
| `L2-04-new-dependency` | 実在する新規依存を追加 | l2-new-deps（検出のみ、非ブロック） |
| `L2-05-sql-injection` | `$queryRawUnsafe` で文字列連結 | l2-semgrep |

### L3（3 ケース）

| ID | 仕込む欠陥 | 期待して止まるゲート |
|---|---|---|
| `L3-01-broken-logic` | 割引計算を壊す | l3-test（回帰検出） |
| `L3-02-openapi-drift` | DTO を変更し `schema.d.ts` を再生成しない | l3-openapi-drift |
| `L3-03-authz-bypass` | 他ユーザーの注文を取得できるようにする | l3-test（後述の要調整あり） |

> **Phase 0 完了時点の申し送り（`L3-03` の期待値を要調整）**：本ケースは当初「e2e の 403 が落ちる」ことを期待値としていたが、Phase 0 で実装した API には **403 を返す経路が存在しない**。`GET /orders` は認証済みユーザー自身の一覧のみを返す設計で、リソース単位の取得（`GET /orders/:id`）が無いため、認可欠落は「403 が出ない」ではなく **「200 で他人のデータが返る」** という形で現れる。
>
> Phase 3 で次のいずれかを選ぶ。**(a)** `GET /orders/:id` を追加して所有者チェックを入れ、403 を返す経路を作る。**(b)** ケースの期待値を「他ユーザーの注文が 200 で混入することを e2e が検出する」に書き換える。
>
> なお Phase 0 の実装は `@UseGuards` を外すと `request.userId` が実行時 `undefined` になり、Prisma が `where: { userId: undefined }` を「条件なし」と解釈して**全ユーザーの注文を返す**。型チェックでも既存の単体テストでも捕まらないため、`L2-02-guard-missing`（Semgrep カスタムルール＝仮説 5）の検証対象としては理想的な形になっている。

### L4（2 ケース）

| ID | 仕込む欠陥 | 期待 |
|---|---|---|
| `L4-01-empty-assertion` | アサーションを `toBeDefined()` だけに緩める | l3-test は緑のまま、l4-mutation だけ赤 |
| `L4-02-off-by-one-fixed-by-test` | 境界値を off-by-one にし、テストもその誤った値に合わせる | l3-test は緑、l4-mutation で露見するか |

L4 の 2 ケースは「L3 が通るのに L4 だけが止める」ことを示せて初めて L4 の追加コストが正当化される。**L3 も一緒に赤になるなら、そのケースは L4 の価値を証明していない**ため、その場合はケースを作り直す。

### L5（3 ケース）

| ID | 仕込む欠陥 | 期待 |
|---|---|---|
| `L5-01-duplicate-logic` | 割引ロジックを Web 側に二重実装 | L1〜L4 全緑、AI レビューが指摘 |
| `L5-02-n-plus-one` | 注文一覧で N+1 クエリ | L1〜L4 全緑、AI レビューが指摘 |
| `L5-03-missing-boundary-test` | 境界値テストを欠落させる | L1〜L4 全緑、AI レビューが指摘 |

L5 の 3 ケースは**「L1〜L4 が全部緑になること」自体が期待値**である。それが成り立つときだけ「L5 は L1〜L4 の上に重ねる補助線」という手順書 §0 の設計原則 3 が裏付けられる。

> **Phase 0 完了時点の申し送り（`L5-02` の前提が崩れている）**：Phase 0 の `orders.service.spec.ts` は `findMany` の呼び出し形（`include: { user: true }` を含む）をアサーションで固定している。これは「N+1 の混入が L3 で捕まるのか L5 でしか捕まらないのかを切り分ける」ために意図的に入れたものだが、その結果 **`L5-02-n-plus-one` は L3 も赤になり**、「L1〜L4 全緑」という期待値を満たさない。
>
> Phase 5 では L4 の 2 ケースと同じ判断基準を適用する。すなわち **L3 も一緒に赤になるならそのケースは L5 の価値を証明していない**ので、次のいずれかを選ぶ。**(a)** クエリ形を固定しているアサーションを外し、N+1 が単体テストをすり抜ける状態にしてから L5 にかける。**(b)** ケースを別の題材（クエリ形を固定していない箇所への N+1 注入）に作り直す。
>
> どちらを選んだかと、そのとき L3 が実際に赤くなったかは `RESULTS.md` に記録する。「単体テストがクエリ形を固定していれば N+1 は L3 で捕まる」という事実自体が、手順書 §10 の「N+1 は L5 で拾う」という割り当てへの反証データになる。

---

## 10. 構築フェーズと完了条件

| Phase | 内容 | 完了条件 |
|---|---|---|
| **0** | モノレポ基盤（pnpm workspace / Turborepo / packages）+ サンプルアプリ（テストは最小） | `pnpm build` が通り、API が `GET /orders` を返し、Web が一覧を表示する |
| **1** | L1（tsconfig 厳格化 + ESLint 共通設定）+ 検証ハーネス骨格 | L1 が緑。L1 系 6 ケースの判定完了。仮説 6・7 に結論 |
| **2** | L2（Semgrep + OSV-Scanner + gitleaks + 新規依存検出） | L2 が緑。L2 系 5 ケースの判定完了。仮説 1・2・3・5 に結論 |
| **3** | L3（Testcontainers / supertest / fast-check / OpenAPI 型生成 / Playwright） | L3 が緑。L3 系 3 ケースの判定完了。仮説 8 に結論 |
| **4** | L4（Stryker を `break: null` で計測 → 閾値設定） | 実測スコア把握 → 閾値設定 → L4 系 2 ケースの判定完了。仮説 4 に結論 |
| **5** | L5 + nightly ローカル実行 + cloudbuild yaml 作成 | L5 系 3 ケースの判定完了。`RESULTS.md` 全 19 ケースが埋まる |
| **6** | 検証レポート作成 | ズレ仮説 8 項目すべてに結論。手順書への修正提案がまとまる |

**Phase 4 の順序が重要である。** 手順書 §5.5 は「いきなり 60% を課すと落ち続ける」と述べているので、`break: null` で実測してから閾値を決める。この実測値自体が「手順書の推奨閾値 60% は現実的か」の検証データになる。

`cloudbuild.pr.yaml` は Phase 5 で作成するが実行しない。`scripts/gates/*.sh` を呼ぶだけの薄い記述にすることで、「ローカルで検証したものと CI で動くものが同一」を担保する。

nightly の検証（Phase 5）では、`stryker run --force` のフル実行と `FC_NUM_RUNS=10000` の深い PBT をローカルで実行し、PR ゲート（差分 + incremental）との結果差を確認する。手順書 §5.4 の「incremental は誤差を持ち込みうる」という警告の実地確認にあたる。

---

## 11. 成果物一覧

| 成果物 | 内容 |
|---|---|
| 動作するゲート環境 | `scripts/gates/*.sh`、各ツール設定、サンプルアプリ |
| `verification/` | 19 ケースのパッチと期待値、実行ハーネス |
| `verification/RESULTS.md` | 検証結果マトリクス（手順書の主張 vs 実測） |
| `docs/` の検証レポート | ズレ仮説 8 項目の結論と手順書への修正提案 |
| `cloudbuild.pr.yaml` / `cloudbuild.nightly.yaml` | 未実行だが `scripts/gates/` を呼ぶ形で作成 |
