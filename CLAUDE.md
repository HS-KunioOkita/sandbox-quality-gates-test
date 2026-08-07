# CLAUDE.md

このリポジトリで作業するエージェント向けの前提知識。ユーザーのグローバル設定とマージされる。

## このリポジトリは何か

`docs/多層品質ゲート_L1-L5_導入手順_NestJS-React.md`（以下「手順書」）が主張する多層品質ゲートの構成を実際に組み、**その主張が本当に成り立つかを実測で検証する**ためのリポジトリ。

サンプルアプリ（会員割引付き注文管理）はゲートを当てる対象にすぎない。**成果物は手順書への修正提案**であり、アプリの機能ではない。

- 設計: `docs/superpowers/specs/2026-07-29-multilayer-quality-gates-verification-design.md`
- **発見と申し送り: `docs/superpowers/phase0-findings.md`** ← 作業前に必ず読む
- 実装計画: `docs/superpowers/plans/`（フェーズ単位）

## 検証の方法

`verification/cases/<CASE-ID>/` に、意図的な欠陥のパッチ（`case.patch`）と期待値（`expect.yml`）を置く。ハーネスが一時ブランチにパッチを当ててゲートを回し、**手順書が「この層が捕まえる」と主張した層が本当に捕まえたか**を判定する。

```bash
./verification/run-case.sh <CASE-ID>   # 1 ケース（Phase 4 の 16 ケース通し実行では 1〜36 秒。ゲート 8 本時代は 21〜39 秒／負荷の高い回は 2〜153 秒。§1.38）
./verification/run-all.sh              # 全ケース + 対照実行、RESULTS.md 生成
./verification/run-l5.sh               # L5 系ケースの n 回反復実測。verification/L5-REVIEW.md を生成（既定 N=5）
```

**`run-all.sh` は必ずバックグラウンドで実行すること。** Bash ツールのタイムアウト上限（10 分）を超える実行を実測している。

**所要時間の絶対値は再現しない。数値を引くときは必ずスコープと実行を明示すること。** 実測は 3 回あり、**対照実行込みで 14 分 35 秒**（3 回目）、**ケース分のみで 6 分 9 秒 / 6 分 1 秒**（初回・2 回目。計測開始位置が対照実行より後ろにあった版）。ケース分だけを比べても 2.3 倍の幅がある。

観測できた差分要因はマシンの負荷である（3 回目の実行中は load average 13.89、Docker の 7.65 GiB のうち 2.65 GiB を無関係な devcontainer が占有。turbo を通さずキャッシュも使わない `l1-lint` が単体 124 秒になっており、ゲート側の変更では説明できない）。判定は 3 回とも完全に同一で、`RESULTS.md` はバイト単位で不変だった。**壁時計を根拠に判断しないこと。** 使えるのはゲート別の相対的な内訳という構造のほうである（§1.38）。

### 絶対に守ること

**`expect.yml` の `expect`（各ゲートの pass/fail）は実測に合わせて更新してよい。`claimed_layer` は絶対に変えてはいけない。**

`expect` は「自分のゲートが今どう振る舞うか」のスナップショットで、初回実行で確定させるのが正しい。一方 `claimed_layer` は**手順書 §10 の主張そのもの**であり、これが検証対象である。実測に合わせて書き換えた瞬間に判定が恒真になり、ハーネスが何も測らなくなる。

同じ理由で、**判定を `match` にするために `case.patch` を書き換えてはいけない**。`mismatch` / `not-caught` が出たなら、それがこのプロジェクトの成果物である。そのまま `RESULTS.md` に残し、原因を `phase0-findings.md` の §1 に書く。

### ハーネスの前提

- ゲートの exit code は `0`=pass / `1`=fail（欠陥を検出）/ `2`=error（ツールが実行できなかった）。**error を fail と誤記録しないことが最重要**（設計書 §6.1）。「Docker が起動していないだけ」を「欠陥を検出した」と読み違えると、検証結果そのものが無意味になる。
- `run-case.sh` は作業ツリーが汚れていると exit 2 で止まる。`git status --porcelain` は未追跡ファイルも報告するので、**ケースを作ったらコミットしてから実行する**。
- `run-all.sh` は追跡ファイルである `RESULTS.md` を書き換える。実行後にコミットするか `git checkout` で戻さないと、次回は全行が「⚠️ 実行不能」になる。
- `run-all.sh` は先頭で対照実行（パッチ無しで全ゲートが pass すること）を確認する。これが赤いとケースの判定は意味を持たないので、その場で止まる。
- `run-l5.sh` も同様に追跡ファイル（`verification/l5-runs/` の生出力と `verification/L5-REVIEW.md`）を書き換えるので、**実行後にコミットが要る**。`l5-ai-review` は `claude -p` を N 回（既定 5）呼ぶため、`run-case.sh` / `run-all.sh` より 1 回あたりの所要が長い。

## 環境

- **`corepack` は入っていない。`corepack enable` を実行しないこと。** pnpm 11.1.1 はグローバルインストール済み（volta 配下）。
- **`gcloud` は入っていない。** 検証はローカル実行のみ。`cloudbuild.*.yaml` は成果物として作るが**実行しない**。
- **Docker Desktop の起動が必須。** `GATE_ORDER` の 4 本（L2 の 3 本 + Phase 3 で `gate_require_docker` を呼ぶようになった `l3-test`）と、`GATE_ORDER` 外の `l3-e2e-web` が Docker 経由で動く。起動していないとゲートは exit 2（error）を返して止まる（fail ではない）。L2 の 3 本のイメージのタグは `scripts/gates/_lib.sh` に固定してある。

  | ゲート | イメージ |
  |---|---|
  | `l2-semgrep` | `semgrep/semgrep:1.171.0` |
  | `l2-osv` | `ghcr.io/google/osv-scanner:v2.4.0` |
  | `l2-gitleaks` | `zricethezav/gitleaks:v8.30.1` |
  | `l3-test`（Testcontainers 経由） | `postgres:16-alpine` |

- **`l4-mutation` は Docker を必要としない。** Stryker が回すのは Jest の unit プロジェクトだけで（`apps/api/jest.stryker.config.ts`）、Testcontainers を使う integration / e2e を含まないため、`gate_require_docker` を呼んでいない（意図的。`phase0-findings.md` §1.49）。上の Docker 必須の一覧に混ぜないこと。

- PostgreSQL は Docker Compose（`pnpm db:up` / `pnpm db:down`。`postgres:16-alpine`）。
- `shellcheck` 0.11.0（brew）。`scripts/gates/*.sh` と `verification/*.sh` を検査する。
- Node v24.11.1。TypeScript は 5.9.3 に固定（ts-jest と typescript-eslint の peer 制約による上限。`phase0-findings.md` §1.4）。
- 依存は全て完全固定（`^` / `~` を付けない）。再現性のため。

## 進め方

- **フェーズは前フェーズの PR がマージされてから着手する。**
- **実装計画はフェーズ単位で書く。** 後半フェーズの内容は前半の実測結果に依存するので、全フェーズ分を先に書かない。
- 計画作成は `superpowers:writing-plans`、実行は `superpowers:subagent-driven-development`。
- 計画作成前に `phase0-findings.md` の §3 から該当フェーズの申し送りを読む。

## この検証で繰り返し出た教訓

**「ゲートが緑」と「ゲートが守っている」は別物である。** Phase 1 で 4 回踏み、Phase 2 でさらに 6 回（踏んだ 4 件 + 踏む前に気づいた 2 件）、Phase 3 で 3 回 + 最終レビューで 1 回観測した。**Phase 4 で踏んだのは 1 件**（`stryker-diff.sh` の `exit 3` と `(none)` の 2 分岐を、コードに書いたまま一度も実行せずに完了報告した。レビューが指摘した）。手順書側の穴の発見 2 件と「踏まなかった」1 件は同じ列で数えない（`phase0-findings.md` §1.13）。ゲートや設定を足したら、**意図的に違反を 1 つ入れて赤くなることを確認する**。緑を確認するだけでは、そのゲートが何も見ていない状態と区別できない。**赤確認は「実際に起こりうる壊し方」で行うこと。** Phase 3 の `l3-test` は Jest（api）を壊す形でしか赤確認しておらず、Vitest（web）だけが落ちる欠陥が error(2) に化けるのを最終レビューまで見逃した（§1.44）。

**テストも同じである。** Phase 2 のレビュー層はこの型の指摘を 7 件出した。テストを足したら、**対象の実装を壊すとそのテストが赤くなること**を確認する。通ることだけを見ても、そのテストが何も固定していない状態と区別できない。

ハーネス自身も例外ではない。ハーネスを変更したら、既に `match` だったケースを再実行して退行していないか確かめる（Phase 1 で実際に退行させた）。

**「ゲートが緑」と「そのゲートを動かし続けられる」も別物である。** Phase 4 の着手時、`pnpm-workspace.yaml` の `trustPolicy: no-downgrade` が `pnpm add` を全面的に拒否し、**Stryker に限らずどの依存も追加できない状態になっていた**（`semver@6.3.1` の provenance 喪失。babel を持つ以上どのパッケージを足しても同じ壁に当たる）。それでも `pnpm install --frozen-lockfile`（`l2-install`）は lockfile を再解決しないので緑を返し続け、**ゲートは全部緑のままだった**（§1.58）。緑は「今の状態が壊れていない」ことしか言わない。次の一手が打てるかは別に確かめる必要がある。

**ある層を足す作業が、別の層のゲートを赤くする。** Phase 3 で 4 回起きた。L3 の依存追加（`@nestjs/swagger` / `openapi-typescript`）が js-yaml の High 脆弱性を持ち込んで `l2-osv` を赤くし（§1.34）、Playwright のテストファイルが vitest の既定 include に拾われて `l3-test` を壊し、同じファイルが ESLint の `projectService` で解決できず `l1-lint` を壊し（§1.36 / §1.37）、`L3-03` の欠陥注入が `l1-typecheck` と `l3-openapi-drift` に同時に当たってケースを判定不能にした（§1.41）。**Phase 4 でさらに 2 回起きた。** Stryker の依存が `fast-uri`（High）と `qs`（Medium）を持ち込んで `l2-osv` を赤くし（§1.59。§1.34 の js-yaml と同型）、Stryker の `json` / `html` レポートがミューテート対象のソース全文を埋め込むため、直前のケースが仕込んだ秘密が次のケースの `l2-gitleaks` に漏れた（§1.55）。**新しい層を足したら、既存の全ゲートを回すまで終わりではない。**

## 現在地

Phase 0（モノレポ基盤とサンプルアプリ）、Phase 1（L1 ゲート + 検証ハーネス + L1 系 6 ケース）、Phase 2（L2 ゲート 4 本 + L2 系 5 ケース）、Phase 3（L3 ゲート 2 本 + L3 系 3 ケース）、Phase 4（L4 ゲート 1 本 + L4 系 2 ケース）、Phase 5（L5 ゲート 1 本 + L5 系 3 ケース + nightly 実測 + cloudbuild）が完了。次は Phase 6（検証レポート作成）。

ブロックするゲートは 9 本（`scripts/gates/gates.list.sh` の `GATE_ORDER`）+ 非ブロック 1 本 + **`GATE_ORDER` 外 2 本**。Playwright（`l3-e2e-web.sh`）は**意図的に `GATE_ORDER` の外**に置いてある（`phase0-findings.md` §1.35）。`l5-ai-review.sh`（AI レビュー）も**意図的に `GATE_ORDER` にも `GATE_DETECTION` にも入れていない**（`claude -p` は非決定的で、1 回の結果を `RESULTS.md` に固定すると誤読を生むため。Phase 5 決定。§1.61 以降）。`apps/web` の Stryker も**意図的に `GATE_ORDER` の外**（nightly 用。§1.48）。

全 19 ケースの結果は `verification/RESULTS.md`（**✅ 10 行 / ❌ 9 行 / ⚠️ 0 行**）。既存 16 ケースは Phase 4 から退行なし（✅ 10 / ❌ 6）で、増えた ❌ 3 行は L5 系 3 ケースである。L1 系は Phase 1 から退行なし（5 件 ✅ / L1-06 のみ ❌）。`run-all.sh` の所要は 5 回の実測で **6 分 9 秒 / 6 分 1 秒（いずれも 14 ケース分・対照実行を含まない）/ 14 分 35 秒（14 ケース + 対照実行）/ 8 分 7 秒（16 ケース + 対照実行 33 秒、ゲート 9 本）/ 8 分 29 秒（19 ケース + 対照実行 22 秒、ゲート 9 本 + 非ブロック 1 本 + `GATE_ORDER` 外 2 本）**。**壁時計を根拠に判断しないこと**（§1.38）。ゲートとケースが増え続けているのに壁時計の値が単調に伸びていないという構造は Phase 3〜5 を通じて繰り返し観測されており、原因はマシン負荷であって高速化の証拠ではない。

`verification/L5-REVIEW.md` は、L5 系 3 ケース × N 回（既定 5）の反復実測を集計した追跡ファイルである。`RESULTS.md` には L5 系ケースの「実際に止めた層」列が出ない（`l5-ai-review` が `GATE_ORDER` / `GATE_DETECTION` の外にあるため）ので、L5 の実測はこちらを見る。`verification/run-l5.sh` が生成し、**実行後にコミットが要る**（上記「ハーネスの前提」参照）。

**`RESULTS.md` の ❌ を読むときの注意**:

- `L3-03-authz-bypass` の ❌ は**意図した結果であり、環境やハーネスの不具合ではない**。手順書 §10 は「認可チェックの欠落」を L2 の担当とし、その具体策として Semgrep カスタムルールを挙げるが、そのルールは Controller に `@UseGuards` が付いているかしか見ない。ガードを残したまま所有者チェックだけを外したこのケースには反応せず、`l3-test` が捕まえた。**手順書 §10 への反証データである**（§1.41）。
- `L2-05-sql-injection` の ❌ も同型。Phase 3 で `l3-test` が捕まえるようになったが、**それは単体テストがクエリの呼び出し形を固定しているからで、SQL インジェクションを検出しているわけではない**（§1.40）。
- **❌ の 9 行と「`claimVerdict` が `mismatch`」の件数は一致しない。** 内訳は `mismatch` 4 件（`L1-06` / `L2-05` / `L3-03` / `L5-02`）、`not-caught` 4 件（`L4-01` / `L4-02` / `L5-01` / `L5-03`）、`match` 1 件（`L2-01-phantom-package`。層の主張は成り立っており、ケースが名指しした `l2-osv` だけが無反応で `claimGateVerdict` のみ `mismatch`。§1.19）。**件数を引くときはどちらの数字か明示すること**（§4 の Phase 5 の表に内訳がある）。
- `L2-04-new-dependency` の ❌ は Phase 3 で解消した。`judge.mjs` に `detectedBy` / `detectingLayers` を足し、非ブロックゲートを「止めた」ではなく「検出した」として照合するようにした（§1.26）。
- **L4 系 2 件の ❌ も意図した結果であり、どちらも手順書への反証データである。** `L4-01-empty-assertion`（アサーションの緩いテスト）は、手順書 §5.3 の差分限定実行が**テストファイルだけの変更に原理的に無反応**であることの実測である。§10 が L4 の担当だと言う落とし穴を、手順書の PR 実行方式は一度も見ない。対照のフル実行ではスコアが 57.14 % → 55.71 % に落ちるが、**閾値 50 は割らないのでフル実行にしてもブロックされない**（§1.56）。`L4-02-off-by-one-fixed-by-test`（誤った実装をテストで固定化する）は、**テストが実装のバグに追従している限り L4 は原理的に検出できない**ことの実測で、スコアは baseline と完全一致した。ミューテーションスコアは「テストが実装のどこを固定しているか」の指標で、「実装が仕様として正しいか」の指標ではない（§1.57）。
- `l4-mutation` は L1 系・L2 系のケースでも fail する（`L1-01` / `L2-03` / `L2-04`）。**欠陥を検出したのではなく、たまたま差分に入ったファイル（`orders.service.ts`。フル実行のスコアが 40 % で閾値 50 を下回る）に反応しているだけである。** 3 ケースのうちスコアの値を実測できているのは `L1-01`（40.00 %）だけで、`L2-03` / `L2-04` は未保存（§1.53）。判定は ✅ のままだが、`expect` の pass/fail を層の独立性の証拠として読まないこと（§1.53）。
- **L5 系 3 件の ❌ も意図した結果であり、環境やハーネスの不具合ではない。** `L5-01-duplicate-logic`（割引ロジックの Web/API 間の重複）と `L5-03-missing-boundary-test`（境界値テストの欠落）は L1〜L4 全て pass、`l5-ai-review` は `GATE_ORDER` の外なので `claimVerdict: not-caught` になる。`L5-01` は §10 が L5 に割り当てた落とし穴に対応するチェックリスト項目が手順書 §6.2 に無いことの実測であり（§1.62）、`L5-03` は対照フル実行のスコアが `L4-01` と数値まで完全一致する（§1.66）。`L5-02-n-plus-one` は既存 spec のクエリ形アサーションに `l3-test` が先に反応し `claimVerdict: mismatch` になる——「N+1 は L5 で拾う」という手順書 §10 の割り当てへの反証データである（§1.65）。3 件とも手順書への反証データとして意図的に残してある。
