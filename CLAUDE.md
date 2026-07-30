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
./verification/run-case.sh <CASE-ID>   # 1 ケース（1〜3 分）
./verification/run-all.sh              # 全ケース + 対照実行、RESULTS.md 生成（15〜25 分）
```

### 絶対に守ること

**`expect.yml` の `expect`（各ゲートの pass/fail）は実測に合わせて更新してよい。`claimed_layer` は絶対に変えてはいけない。**

`expect` は「自分のゲートが今どう振る舞うか」のスナップショットで、初回実行で確定させるのが正しい。一方 `claimed_layer` は**手順書 §10 の主張そのもの**であり、これが検証対象である。実測に合わせて書き換えた瞬間に判定が恒真になり、ハーネスが何も測らなくなる。

同じ理由で、**判定を `match` にするために `case.patch` を書き換えてはいけない**。`mismatch` / `not-caught` が出たなら、それがこのプロジェクトの成果物である。そのまま `RESULTS.md` に残し、原因を `phase0-findings.md` の §1 に書く。

### ハーネスの前提

- ゲートの exit code は `0`=pass / `1`=fail（欠陥を検出）/ `2`=error（ツールが実行できなかった）。**error を fail と誤記録しないことが最重要**（設計書 §6.1）。「Docker が起動していないだけ」を「欠陥を検出した」と読み違えると、検証結果そのものが無意味になる。
- `run-case.sh` は作業ツリーが汚れていると exit 2 で止まる。`git status --porcelain` は未追跡ファイルも報告するので、**ケースを作ったらコミットしてから実行する**。
- `run-all.sh` は追跡ファイルである `RESULTS.md` を書き換える。実行後にコミットするか `git checkout` で戻さないと、次回は全行が「⚠️ 実行不能」になる。
- `run-all.sh` は先頭で対照実行（パッチ無しで全ゲートが pass すること）を確認する。これが赤いとケースの判定は意味を持たないので、その場で止まる。

## 環境

- **`corepack` は入っていない。`corepack enable` を実行しないこと。** pnpm 11.1.1 はグローバルインストール済み（volta 配下）。
- **`gcloud` は入っていない。** 検証はローカル実行のみ。`cloudbuild.*.yaml` は成果物として作るが**実行しない**。
- PostgreSQL は Docker Compose（`pnpm db:up` / `pnpm db:down`）。
- Node v24.11.1。TypeScript は 5.9.3 に固定（ts-jest と typescript-eslint の peer 制約による上限。`phase0-findings.md` §1.4）。
- 依存は全て完全固定（`^` / `~` を付けない）。再現性のため。

## 進め方

- **フェーズは前フェーズの PR がマージされてから着手する。**
- **実装計画はフェーズ単位で書く。** 後半フェーズの内容は前半の実測結果に依存するので、全フェーズ分を先に書かない。
- 計画作成は `superpowers:writing-plans`、実行は `superpowers:subagent-driven-development`。
- 計画作成前に `phase0-findings.md` の §3 から該当フェーズの申し送りを読む。

## この検証で繰り返し出た教訓

**「ゲートが緑」と「ゲートが守っている」は別物である。** Phase 1 だけで 4 回踏んだ（`phase0-findings.md` §1.13）。ゲートや設定を足したら、**意図的に違反を 1 つ入れて赤くなることを確認する**。緑を確認するだけでは、そのゲートが何も見ていない状態と区別できない。

ハーネス自身も例外ではない。ハーネスを変更したら、既に `match` だったケースを再実行して退行していないか確かめる（Phase 1 で実際に退行させた）。

## 現在地

Phase 0（モノレポ基盤とサンプルアプリ）と Phase 1（L1 ゲート + 検証ハーネス + L1 系 6 ケース）が完了。次は Phase 2（L2: Semgrep / OSV-Scanner / gitleaks / 新規依存検出）。

L1 系 6 ケースの結果は `verification/RESULTS.md`。5 件で手順書の主張どおりの層が捕まえ、**1 件（L1-06）はどの層も捕まえなかった**。
