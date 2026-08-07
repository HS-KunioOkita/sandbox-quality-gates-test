# Phase 5（L5: AI レビュー）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手順書 §6（L5 = AI レビュー）と §7（cloudbuild）を実装し、L5 系 3 ケースの判定と同一差分 5 回の反復実測を出して、設計原則 3（L5 は L1〜L4 の上に重ねる補助線）・§6.1（LLM の判定は非頑健）・§6.2 のチェックリストの網羅性の 3 つに結論を与える。

**Architecture:** `.claude/skills/code-review/SKILL.md` を手順書 §6.2 の逐語で置き、`scripts/gates/l5-ai-review.sh` が `claude -p "/code-review <base>...HEAD"` を呼んで生出力をファイルに残す。このゲートは `GATE_ORDER` にも `GATE_DETECTION` にも入れない（`claude -p` の非決定性を `RESULTS.md` に持ち込まないため）。代わりに `verification/run-l5.sh` が 3 ケース × 5 回を回し、生出力 15 本と機械判定の集計を `verification/L5-REVIEW.md` に出す。

**Tech Stack:** Claude Code CLI 2.1.221（`claude -p`）、bash 3.2、Node v24.11.1、pnpm 11.1.1、shellcheck 0.11.0。新しい npm 依存は追加しない。

## Global Constraints

このリポジトリ固有の規律。**全タスクの受け入れ条件に暗黙に含まれる。**

- **`expect.yml` の `claimed_layer` は絶対に変えてはいけない。** 手順書 §10 の主張そのものであり、これが検証対象である。`expect`（各ゲートの pass/fail）は実測に合わせて更新してよい。
- **判定を `match` にするために `case.patch` を書き換えてはいけない。** `mismatch` / `not-caught` が出たなら、それがこのプロジェクトの成果物である。
- ゲートの exit code は `0`=pass / `1`=fail（欠陥を検出）/ `2`=error（ツールが実行できなかった）。**error を fail と誤記録しないことが最重要**（設計書 §6.1）。
- **`corepack enable` を実行しない。** pnpm 11.1.1 はグローバルインストール済み。
- **`pnpm-workspace.yaml` の `minimumReleaseAge` / `minimumReleaseAgeExclude` / `overrides` を自分の判断で編集しない。** 本フェーズは npm 依存を追加しない予定だが、何らかの理由で必要になったら**状況を報告して人間の判断を仰いで停止する**。
- ケースを作ったら**コミットしてから** `run-case.sh` を実行する（`git status --porcelain` は未追跡ファイルも報告し、汚れたツリーでは exit 2 で止まる）。
- **`run-all.sh` と `run-l5.sh` は必ずバックグラウンドで実行する。** Bash ツールのタイムアウト上限（10 分）を超える実行を実測している。
- `run-all.sh` は追跡ファイルの `RESULTS.md` を、`run-l5.sh` は `L5-REVIEW.md` と `verification/l5-runs/` を書き換える。**実行後にコミットするか `git checkout` で戻す。**
- **壁時計の絶対値を根拠に判断しない。** 同一条件で 2.3 倍の幅が出る（§1.38）。数値を引くときはスコープと実行を明示する。
- **ゲートやスクリプトを足したら、意図的に違反を 1 つ入れて赤くなることを確認する。** 赤確認は「実際に起こりうる壊し方」で行う（§1.13 / §1.44）。緑の確認だけでは、そのゲートが何も見ていない状態と区別できない。
- 新しい層を足したら、**既存の全ゲートを回すまで終わりではない**（Phase 3 で 4 回、Phase 4 で 2 回、層をまたぐ相互作用が起きた）。
- Docker Desktop の起動が必須（`l2-semgrep` / `l2-osv` / `l2-gitleaks` / `l3-test`、および Task 6 の `l3-e2e-web`）。
- `shellcheck` 0.11.0 で `scripts/gates/*.sh` `scripts/stryker-diff.sh` `verification/*.sh` を検査し、指摘 0 を保つ。
- bash は **3.2**（macOS 標準）。連想配列（`declare -A`）や `${var,,}` は使えない。
- **`gcloud` は入っていない。`cloudbuild.*.yaml` は作るが実行しない。**

## ブレインストーミングで確定した決定

| # | 決定 |
|---|---|
| D1 | `l5-ai-review` は `GATE_ORDER` / `GATE_DETECTION` の**外**。反復実測で測る |
| D2 | `L5-02` は設計書どおり `orders.service.ts` に N+1 を注入し、既存 spec は触らない |
| D3 | ハーネス改善は **#41 のみ**。#40（`--mutate` の除外再適用）と #27（ルール ID 照合）は Phase 6 へ |
| D4 | nightly 実測は **Playwright フル**と **web Stryker 差分限定（#34）**。`FC_NUM_RUNS=10000` は §1.31 で実測済みなので再実測しない |
| D5 | 反復実測は**同一モデル 5 回 × 3 ケース = 15 実行** |
| D6 | 判定は**機械判定を主軸にし、生出力 15 本を全部保存する** |

## 手順書からの逸脱（4 点。すべてコメントと findings に理由を書く）

| 逸脱 | 理由 |
|---|---|
| **`l5-ai-review` を `GATE_DETECTION` に入れない** | 手順書 §7 は L5 を PR パイプラインのステップとして書くが、`claude -p` は非決定的で、1 回の結果を `RESULTS.md` に恒久的な事実として固定すると誤読を生む（D1） |
| **`corepack enable` を cloudbuild に書かない** | このリポジトリに `corepack` が無い（#37(a)） |
| **cloudbuild の各ステップに `GATE_BASE_REF` を明示的に渡す** | `stryker-diff.sh` / `l2-new-deps.sh` から `git fetch` を外したため（#37(b)） |
| **cloudbuild の `l3-test` に `--filter='...[origin/main]'` を使わない** | 対象 0 件でも exit 0 になり「何が走ったか分からない緑」を作る（§1.43） |

## ファイル構成

| ファイル | 責務 | タスク |
|---|---|---|
| `.claude/skills/code-review/SKILL.md` | 新規。手順書 §6.2 の逐語 | 1 |
| `scripts/gates/l5-ai-review.sh` | 新規。`claude -p` を呼び生出力を残す。`GATE_ORDER` 外 | 2 |
| `scripts/gates/gates.test.sh` | 変更。`l5-ai-review` の error 経路（Task 2）と Stryker 実起動（Task 5）を足す | 2, 5 |
| `verification/cases/L5-01-duplicate-logic/` | 新規。`case.patch` + `expect.yml` | 3 |
| `verification/cases/L5-02-n-plus-one/` | 新規。同上 | 3 |
| `verification/cases/L5-03-missing-boundary-test/` | 新規。同上 | 3 |
| `verification/run-l5.sh` | 新規。3 ケース × 5 回の反復実測と集計 | 4 |
| `verification/l5-runs/<CASE-ID>/run-N.md` | 生成物（追跡する）。生出力 15 本 | 4 |
| `verification/L5-REVIEW.md` | 生成物（追跡する）。反復実測の集計表 | 4 |
| `cloudbuild.pr.yaml` | 新規。未実行。`scripts/gates/*.sh` を呼ぶ薄い記述 | 7 |
| `cloudbuild.nightly.yaml` | 新規。未実行 | 7 |
| `verification/RESULTS.md` | 生成物。19 ケース分に更新 | 8 |
| `docs/superpowers/phase0-findings.md` | 変更。§1.61 以降に発見、§3 の Phase 5 表を完了済みに、§4 に受け入れ確認記録 | 8 |
| `CLAUDE.md` | 変更。「現在地」を 19 ケース / Phase 5 完了に更新 | 8 |

---

## Task 1: `/code-review` の名前衝突を実測し、`SKILL.md` を置く

**このタスクの結論が Task 2 と Task 4 の実装を左右する。** `/code-review` は Claude Code の組み込みコマンドとして既に存在するため、手順書 §6.2 が指定する `.claude/skills/code-review/SKILL.md` を置いても読まれない可能性がある。**先に実測する。**

**Files:**
- Create: `.claude/skills/code-review/SKILL.md`
- Create: `docs/superpowers/l5-name-collision.md`（実測記録。Task 8 で findings に取り込む）

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces: 「`claude -p "/code-review ..."` が呼ぶのは組み込みか SKILL.md か」の実測結果と、その出力形式のサンプル。Task 2 の `l5-ai-review.sh` が渡すプロンプト文字列と、Task 4 の機械判定が grep する対象がこれで決まる

- [ ] **Step 1: 実測用の差分を持つ一時ブランチを作る**

作業ツリーがクリーンであることを確認してから実行する。

```bash
git status --porcelain   # 空であること
git checkout -b tmp/l5-collision-probe
```

`apps/api/src/discount/discount.spec.ts` から境界値テストを 1 件だけ削除する。**削除するのはこのブロックだけ**（`it('会員で閾値のすぐ下のときは割引されない', ...)`）。

```ts
  it('会員で閾値のすぐ下のときは割引されない', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE - 1, true)).toBe(999);
  });

```

境界値の欠落を選ぶ理由は、手順書 §6.2 のチェックリスト 1 項目目（「境界値：閾値のちょうど上・ちょうど・すぐ下のテストがあるか」）に真正面から当たるためである。SKILL.md が読まれていれば、この項目に「該当」と出るはずである。

```bash
git commit -am "tmp: 境界値テストを 1 件削除（衝突実測用）"
```

- [ ] **Step 2: SKILL.md が無い状態で `/code-review` を実行し、出力を保存する**

```bash
mkdir -p /tmp/l5-probe
claude -p "/code-review main...HEAD" --output-format text > /tmp/l5-probe/before.md 2>&1
wc -l /tmp/l5-probe/before.md
```

**この実行には数十秒〜数分かかる。** タイムアウトを 600000（10 分）に設定して実行する。

期待: 何らかのレビュー出力が得られる。空ファイルや「Unknown slash command」で終わった場合は、その事実自体が実測結果なので `before.md` を保存したまま次へ進む。

- [ ] **Step 3: 手順書 §6.2 の逐語で `SKILL.md` を作る**

`.claude/skills/code-review/SKILL.md` を作る。**手順書 §6.2 のコードブロックの中身を一字一句そのまま写す。** 改善・補足・このリポジトリ向けの調整を加えてはいけない。逐語であることがこの検証の前提である。

```markdown
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

**注意:** 手順書の原文には `<!-- .claude/skills/code-review/SKILL.md -->` というコメント行が先頭にある。これはファイルの置き場所を示すための注釈なので、SKILL.md の中身には含めない。frontmatter から始める。

- [ ] **Step 4: SKILL.md がある状態で同じコマンドを実行し、出力を保存する**

```bash
git add .claude/skills/code-review/SKILL.md
git commit -m "tmp: SKILL.md を追加（衝突実測用）"
claude -p "/code-review main...HEAD" --output-format text > /tmp/l5-probe/after.md 2>&1
wc -l /tmp/l5-probe/after.md
```

同じくタイムアウト 600000 で実行する。

- [ ] **Step 5: 2 つの出力を比較して、どちらが呼ばれたかを判定する**

```bash
diff /tmp/l5-probe/before.md /tmp/l5-probe/after.md | head -40
grep -c '境界値\|異常系\|冪等性\|並行性\|トランザクション境界' /tmp/l5-probe/after.md
grep -c '境界値\|異常系\|冪等性\|並行性\|トランザクション境界' /tmp/l5-probe/before.md
```

判定基準:

| 観測 | 結論 |
|---|---|
| `after.md` にチェックリスト 8 項目の見出し語が並び、`before.md` には並ばない | **SKILL.md が読まれている**。手順書どおり |
| 両方に並ばない、または 2 つの出力が実質同一 | **組み込みが優先されている**。手順書 §6.2 の指示は空振りする |
| `before.md` が「Unknown slash command」等で `after.md` は正常 | SKILL.md が読まれている（組み込みは存在しない） |

- [ ] **Step 6: 実測結果を記録する**

`docs/superpowers/l5-name-collision.md` に次を書く。Task 8 で findings の §1.61 に取り込む。

- 実行した 2 つのコマンド（逐語）
- それぞれの出力の冒頭 30 行
- 上表のどの行に当たったか
- **組み込みが優先された場合の回避策と、その選択理由**——スキル名を変える（`.claude/skills/l5-review/SKILL.md` にして `claude -p "/l5-review ..."` を呼ぶ）か、`claude -p` にチェックリスト本文を直接渡すか。**回避策を採った場合、その挙動を「手順書逐語の挙動」として記録してはいけない。** 2 つを別の節に分けて書く

- [ ] **Step 7: 一時ブランチを片付け、SKILL.md を本ブランチに置く**

```bash
git checkout feat/phase5-l5-ai-review
git branch -D tmp/l5-collision-probe
```

`.claude/skills/code-review/SKILL.md`（Step 3 と同一内容）を作り直す。組み込みが優先されると判明した場合は、**手順書逐語の `code-review` はそのまま残したうえで**、回避策用のスキル（例 `.claude/skills/l5-review/SKILL.md`、中身は `code-review` と同一で `name` だけ変える）を追加する。手順書逐語のファイルを消してはいけない。それが検証対象だからである。

- [ ] **Step 8: L1 ゲートが緑のままであることを確認してコミットする**

`.claude/` 配下は TypeScript でも shell でもないが、追跡ファイルが増えると `l2-gitleaks`（`--no-git` で作業ツリー全体を走査する）の対象になる。

```bash
./scripts/gates/l1-lint.sh; echo "l1-lint exit=$?"
./scripts/gates/l2-gitleaks.sh; echo "l2-gitleaks exit=$?"
```

期待: 両方 0。

```bash
git add .claude docs/superpowers/l5-name-collision.md
git commit -m "feat(l5): 手順書 §6.2 逐語の code-review スキルを追加し、/code-review の名前衝突を実測する"
```

---

## Task 2: `scripts/gates/l5-ai-review.sh` を作る

**Files:**
- Create: `scripts/gates/l5-ai-review.sh`
- Modify: `scripts/gates/gates.test.sh`（末尾に L5 の error 経路 2 件を追加）

**Interfaces:**
- Consumes: Task 1 が確定させた「どのスラッシュコマンドを呼ぶか」
- Produces: `scripts/gates/l5-ai-review.sh`。環境変数 `GATE_BASE_REF`（比較対象 ref、既定 `origin/main`）と `L5_REVIEW_OUT`（出力先パス、既定 `reports/l5/review.md`）を読む。exit code は 0 固定、実行不能時のみ 2。Task 4 の `run-l5.sh` が `L5_REVIEW_OUT` を 5 回別々に指定して呼ぶ

- [ ] **Step 1: ゲートスクリプトを書く**

`scripts/gates/l5-ai-review.sh`:

```bash
#!/usr/bin/env bash
# L5: AI レビュー（手順書 §6）
#
# GATE_ORDER にも GATE_DETECTION にも入れない。claude -p は非決定的で、
# 1 回の実行結果を RESULTS.md に恒久的な事実として固定すると誤読を生むため
# （Phase 5 の決定 D1）。反復実測は verification/run-l5.sh が行う。
#
# 手順書 §6.1 は「ブロックさせません」と明記し、§6.3 は `|| true` で
# ビルドを落とさない形を示している。したがって exit code は 0 固定で、
# claude 自体を起動できなかったときだけ 2（error）を返す。
#
# **このゲートは「検出したか」を判定しない。** 何を検出すべきかはケースごとに
# 異なり（L5-02 は N+1、L5-03 は境界値）、ゲート側に持たせるとケース依存の
# 知識がゲートに漏れる。ゲートは生出力をファイルに残すだけにして、判定は
# run-l5.sh に置く。l2-new-deps.sh が marker を出すのとは意図的に異なる。
#
# 出力先は reports/ 配下（.gitignore 済み）。差分の内容——秘密を含みうる——を
# 埋め込むため、追跡ファイルとして残すと次のケースの l2-gitleaks が拾う
# （§1.55 が Stryker のレポートで実測した経路と同型）。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd claude
gate_require_cmd git

BASE_REF="${GATE_BASE_REF:-origin/main}"
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  printf 'gate error: 比較対象の ref が見つかりません: %s\n' "$BASE_REF" >&2
  exit "$GATE_ERROR"
fi

OUT="${L5_REVIEW_OUT:-reports/l5/review.md}"
mkdir -p "${OUT%/*}" || exit 2

# 手順書 §6.3 の逐語は `claude -p "/code-review origin/$_BASE_BRANCH...HEAD"`。
# 比較対象だけを GATE_BASE_REF に置き換える（l2-new-deps.sh と同じ規約。#37(b)）。
claude -p "/code-review $BASE_REF...HEAD" --output-format text >"$OUT" 2>&1
raw=$?

# 手順書 §6.3 の `|| true` に相当する。claude が非ゼロで終わっても
# ブロックしない。ただし何が起きたかは残す。
if [ "$raw" -ne 0 ]; then
  printf 'L5_REVIEW_CLAUDE_EXIT=%s\n' "$raw"
fi

printf 'L5_REVIEW_OUT=%s\n' "$OUT"
exit "$GATE_PASS"
```

**`gate_require_cmd claude` を入れる理由:** `claude` が PATH に無い状態で実行すると、`claude ... > "$OUT"` は出力を空にしたまま非ゼロを返す。それを exit 0 で返すと「AI レビューが何も指摘しなかった」と「AI レビューが動かなかった」が区別できなくなる。§1.13 が繰り返し観測している「緑と守っているは別物」の型そのものなので、入口で error(2) に落とす。

- [ ] **Step 2: shellcheck を通す**

```bash
shellcheck scripts/gates/l5-ai-review.sh
```

期待: 指摘 0。

- [ ] **Step 3: 差分がある状態で実行し、出力が残ることを確認する**

現在のブランチは Task 1 のコミットを含むので `main` との差分がある。

```bash
chmod +x scripts/gates/l5-ai-review.sh
GATE_BASE_REF=main L5_REVIEW_OUT=/tmp/l5-smoke.md ./scripts/gates/l5-ai-review.sh
echo "exit=$?"
wc -l /tmp/l5-smoke.md
head -20 /tmp/l5-smoke.md
```

タイムアウト 600000 で実行する。

期待: exit 0、`L5_REVIEW_OUT=/tmp/l5-smoke.md` が標準出力に出る、`/tmp/l5-smoke.md` が空でない。

- [ ] **Step 4: 赤確認——error(2) の 2 経路を実際に踏む**

このゲートは非ブロックなので「赤くなる」ことがない。代わりに**「実行できなかったときに error(2) になる」ことを実際に踏んで確認する**。これを確認しないと、`claude` が動いていないのに緑を返す状態と区別できない。

```bash
# (a) claude が PATH に無い
env -i PATH=/usr/bin:/bin HOME="$HOME" bash ./scripts/gates/l5-ai-review.sh; echo "no-claude exit=$?"
# (b) 比較対象の ref が存在しない
GATE_BASE_REF=refs/heads/does-not-exist ./scripts/gates/l5-ai-review.sh; echo "bad-ref exit=$?"
```

期待: 両方 2。

**(a) で 2 にならなかったら止まる。** `claude` が `/usr/bin` や `/bin` に入っている場合は PATH を絞っても消えない。その場合は `command -v claude` の出力を確認し、ガードが機能する形の再現方法（`PATH` から該当ディレクトリだけを外す）に変えてから再実行する。

- [ ] **Step 5: `gates.test.sh` に上の 2 件を足す**

`scripts/gates/gates.test.sh` の末尾（「どのカレントディレクトリからでも動く」の節の後）に追加する。既存の `check <名前> <期待> <実測>` の形に合わせる。

```bash
# --- L5（非ブロック・GATE_ORDER 外）の error 経路 ---
# l5-ai-review は exit code で欠陥を主張しない（常に 0）。したがって
# 「動かなかったのに緑」を防げるのは error(2) のガードだけである。そこを直接突く。
GATE_BASE_REF=refs/heads/does-not-exist ./scripts/gates/l5-ai-review.sh >/dev/null 2>&1
check 'l5-ai-review は比較対象が無いとき error' 2 "$?"

env -i PATH=/usr/bin:/bin HOME="$HOME" bash ./scripts/gates/l5-ai-review.sh >/dev/null 2>&1
check 'l5-ai-review は claude が無いとき error' 2 "$?"
```

- [ ] **Step 6: `gates.test.sh` を全件実行する**

```bash
./scripts/gates/gates.test.sh
echo "exit=$?"
```

期待: 全件 pass、exit 0。件数が既存 + 2 件に増えていること。**件数を控えておく**（Task 5 でさらに増やし、Task 8 で findings に記録する）。

- [ ] **Step 7: shellcheck と commit**

```bash
shellcheck scripts/gates/gates.test.sh scripts/gates/l5-ai-review.sh
git add scripts/gates/l5-ai-review.sh scripts/gates/gates.test.sh
git commit -m "feat(l5): l5-ai-review ゲートを追加（GATE_ORDER 外・非ブロック）"
```

---

## Task 3: L5 系 3 ケースを作り、`run-case.sh` で実測して `expect.yml` を確定する

**Files:**
- Create: `verification/cases/L5-01-duplicate-logic/case.patch`, `expect.yml`
- Create: `verification/cases/L5-02-n-plus-one/case.patch`, `expect.yml`
- Create: `verification/cases/L5-03-missing-boundary-test/case.patch`, `expect.yml`

**Interfaces:**
- Consumes: なし（ハーネスの既存規約に従うだけ）
- Produces: 3 つのケースディレクトリ。Task 4 の `run-l5.sh` がこの 3 つの `case.patch` を当てる。Task 8 の `run-all.sh` が 19 ケースとして拾う

**パッチの作り方（3 ケース共通の手順）:** 対象ファイルを編集 → `git diff > verification/cases/<ID>/case.patch` → `git checkout -- <対象ファイル>` で編集を戻す → `case.patch` と `expect.yml` を追加してコミット。**ケースをコミットしてから `run-case.sh` を実行する**（未追跡ファイルがあると exit 2）。

- [ ] **Step 1: `L5-01-duplicate-logic` のパッチを作る**

`apps/web/src/features/orders/orderTotal.ts` の `isDiscountApplied` を、API が返した `discountedTotal` との比較から、`@repo/shared` の閾値を使った独自判定に変える。

変更前:

```ts
/** この注文に割引が効いているか */
export function isDiscountApplied(order: OrderView): boolean {
  return order.discountedTotal < order.unitPrice * order.quantity;
}
```

変更後:

```ts
/** この注文に割引が効いているか */
export function isDiscountApplied(order: OrderView): boolean {
  // API の discountedTotal を見ずに、割引条件を web 側で再判定する
  return order.unitPrice * order.quantity >= MEMBER_DISCOUNT_MIN_PRICE;
}
```

import 行も追加する（ファイル先頭）:

```ts
import { MEMBER_DISCOUNT_MIN_PRICE } from '@repo/shared';
```

**この欠陥が現実的である理由:** 会員かどうかは `OrderView` に含まれていないので、web 側で割引の有無を判定するには金額の閾値から推測するしかない。非会員の 1200 円の注文に「割引」バッジが誤表示される。割引の適用条件（閾値 1000 円）が API と Web の 2 箇所に書かれた状態＝手順書 §10 の「設計の一貫性が崩れ、重複が増える」そのものである。

**既存テストが通ることを先に確認する。** これが落ちると `l3-test` が赤くなり、L5 の検証にならない。

- `orderTotal.test.ts`: `isDiscountApplied(unitPrice:1200, quantity:1)` → 1200 >= 1000 → `true`（期待 true）。`isDiscountApplied(unitPrice:300, quantity:2)` → 600 >= 1000 → `false`（期待 false）。**両方通る**
- `OrderList.test.tsx`: `SAMPLE_ORDERS` はキーボード（1200 × 1 = 1200）とケーブル（300 × 2 = 600）。前者だけが割引表示になる（期待どおり）

```bash
# 編集後、パッチを取る前に確認する
pnpm --filter web exec vitest run
```

期待: 全件 pass。**落ちたらパッチの内容を見直す**（判定を match にするための書き換えではなく、「L1〜L4 全緑になる欠陥」というケースの前提を満たすための設計である）。

```bash
git diff > verification/cases/L5-01-duplicate-logic/case.patch
git checkout -- apps/web/src/features/orders/orderTotal.ts
```

- [ ] **Step 2: `L5-01` の `expect.yml` を書く**

```yaml
id: L5-01-duplicate-logic
pitfall: 割引ロジックを Web 側に二重実装する
claimed_layer: L5
# 手順書 §10 は「設計の一貫性が崩れ、重複が増える」を L5 / 人間 に割り当て、
# 具体策として「チェックリスト＋CODEOWNERS」を挙げている。
claimed_gate: l5-ai-review
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: pass
  l3-openapi-drift: pass
  # apps/web しか触らないため stryker-diff.sh の差分（apps/api/src 配下の
  # 非 spec .ts）が 0 件になり、L4_MUTATE_FILES=(none) でスキップされる。
  l4-mutation: pass
expect_detection:
  l2-new-deps: false
```

**`expect` の値は Step 5 の実測で確定させる。** ここに書くのは予測であり、実測と食い違ったら**実測に合わせて `expect` を更新する**（`claimed_layer` は変えない）。

- [ ] **Step 3: `L5-02-n-plus-one` のパッチを作る**

`apps/api/src/orders/orders.service.ts` の `findByUser` を N+1 にする。

変更前:

```ts
  async findByUser(userId: string): Promise<OrderResponseDto[]> {
    const orders = await this.prisma.order.findMany({
      where: { userId },
      include: { user: true },
      orderBy: { createdAt: 'desc' },
    });

    return orders.map(toOrderResponse);
  }
```

変更後:

```ts
  async findByUser(userId: string): Promise<OrderResponseDto[]> {
    const orders = await this.prisma.order.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });

    const withUser = [];
    for (const order of orders) {
      const user = await this.prisma.user.findUniqueOrThrow({ where: { id: order.userId } });
      withUser.push({ ...order, user });
    }

    return withUser.map(toOrderResponse);
  }
```

**予測される挙動:** `orders.service.spec.ts` は `findMany` が `include: { user: true }` 付きで呼ばれることをアサーションで固定しているうえ、mock は `{ order: { findMany, create } }` しか持たない（`prisma.user` が `undefined`）。したがって `l3-test` が赤くなる。`run-case.sh` の規約により `l4-mutation` は実行されない（§1.54）。

**ループ内 `await` が `l1-lint` に引っかからないか確認する。** `no-await-in-loop` は typescript-eslint の推奨セットには含まれていないが、このリポジトリの設定に入っていれば L1 で捕まってケースが判定不能になる（§1.41 と同型）。

```bash
pnpm eslint apps/api/src/orders/orders.service.ts --max-warnings=0
echo "exit=$?"
```

期待: 0。**非ゼロならケースが L1 に当たる**ので、その事実を記録したうえで `for...of` を `Promise.all` + `map` に変える（N+1 であることは変わらない）。

- [ ] **Step 4: `L5-02` の `expect.yml` を書く**

```yaml
id: L5-02-n-plus-one
pitfall: 注文一覧で N+1 クエリを発生させる
claimed_layer: L5
# 手順書 §6.2 のチェックリストは「N+1：ORM のクエリが件数に比例して増えないか」を
# L5 の観点として挙げている。
claimed_gate: l5-ai-review
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  # 実測で確定させる。orders.service.spec.ts が findMany の呼び出し形
  # （include: { user: true } を含む）をアサーションで固定しており、
  # mock は prisma.user を持たない。
  l3-test: fail
  l3-openapi-drift: pass
  # l3-test が pass しないため run-case.sh は l4-mutation を実行しない
  # （§1.54）。TSV に行が出ないので expect からも外す。
expect_detection:
  l2-new-deps: false
```

**`l4-mutation` の行を書かない。** 実行されないゲートを `expect` に書くと `judge()` が `not-run` の mismatch を出す。既存の `l3-test: fail` のケース 5 件（`L1-03` / `L2-02` / `L2-05` / `L3-01` / `L3-03`）はすべて `l4-mutation` を `expect` から外し、その理由をコメントで残している。**同じ体裁のコメントを書くこと**（既存の 1 件を読んで文面を揃える）。

- [ ] **Step 5: `L5-03-missing-boundary-test` のパッチを作る**

`apps/api/src/discount/discount.spec.ts` から境界値テスト 3 件を削除する。削除するのは次の 3 ブロックだけで、他のテスト（非会員・端数切り捨て・0 円・プロパティ 3 件）は残す。

```ts
  it('会員で閾値ちょうどのときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE, true)).toBe(900);
  });

  it('会員で閾値のすぐ下のときは割引されない', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE - 1, true)).toBe(999);
  });

  it('会員で閾値のすぐ上のときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE + 1, true)).toBe(900);
  });
```

削除により `MEMBER_DISCOUNT_MIN_PRICE` の import が未使用になるかを確認する。プロパティテストは使っていないので**未使用になる可能性が高い**。未使用なら `l1-lint`（`no-unused-vars`）が赤くなり、ケースが L1 に当たって判定不能になる（§1.41 と同型）。

```bash
pnpm eslint apps/api/src/discount/discount.spec.ts --max-warnings=0
echo "exit=$?"
```

非ゼロなら import 行も削除する（`import { MEMBER_DISCOUNT_MIN_PRICE } from '@repo/shared';`）。**その場合、パッチが「テストの削除」に加えて「import の削除」を含むことになるが、これは同一の欠陥の一部（テストを消した結果）なので分割しなくてよい。** `expect.yml` のコメントにその旨を書く。

- [ ] **Step 6: `L5-03` の `expect.yml` を書く**

```yaml
id: L5-03-missing-boundary-test
pitfall: 境界値テストを欠落させる
claimed_layer: L5
# 手順書 §6.2 のチェックリスト 1 項目目「境界値：閾値のちょうど上・ちょうど・
# すぐ下のテストがあるか」に真正面から当たる。
claimed_gate: l5-ai-review
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
  l3-test: pass
  l3-openapi-drift: pass
  # spec のみを触るため stryker-diff.sh の差分が 0 件になり、
  # L4_MUTATE_FILES=(none) でスキップされる。L4-01 と同型（§1.56）。
  l4-mutation: pass
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 7: 3 ケースをコミットして 1 件ずつ実測する**

```bash
git add verification/cases/L5-01-duplicate-logic verification/cases/L5-02-n-plus-one verification/cases/L5-03-missing-boundary-test
git commit -m "test(l5): L5 系 3 ケースを追加"
```

1 件ずつ実行する（各ケース 1〜36 秒、L5-02 は L4 がスキップされるぶん短い見込み）。

```bash
./verification/run-case.sh L5-01-duplicate-logic
./verification/run-case.sh L5-02-n-plus-one
./verification/run-case.sh L5-03-missing-boundary-test
```

各実行の JSON 出力（`claimVerdict` / `blockedBy` / `mismatches`）を控える。

- [ ] **Step 8: 実測に合わせて `expect` を更新する**

`mismatches` が空でないケースは、**`expect` の pass/fail を実測に合わせて書き換える**。`claimed_layer` と `claimed_gate` は変えない。`case.patch` も変えない。

書き換えたら、なぜその値になったのかを `expect.yml` のコメントに実測ベースで書く（「〜と予測される」ではなく「実測: 〜」の形にする）。

再実行して `configVerdict: match` になることを確認する。

```bash
git add verification/cases/L5-0*/expect.yml
git commit -m "test(l5): L5 系 3 ケースの expect を実測に合わせて確定する"
```

- [ ] **Step 9: `L5-03` の対照フル実行を取る**

差分限定実行では `l4-mutation` がスキップされるが、フル実行なら境界値テストの欠落が `discount.ts` の mutant 生存として現れるはずである。`L4-01`（§1.56）と同型の実測になる。

```bash
git checkout -b tmp/l5-03-fullrun
git apply --index verification/cases/L5-03-missing-boundary-test/case.patch
git commit -m "tmp: L5-03 のパッチ（フル実行の対照用）"
pnpm --filter api exec stryker run 2>&1 | tail -40
```

タイムアウト 600000 で実行する。**`--force` は付けない**（`incremental: false` なので不要。Phase 4 と同じ条件で比較するため）。

出力の `Mutation score` と、`discount.ts` の生存 mutant 数を控える。baseline は **57.14 %**（Phase 4 の実測）。

```bash
git checkout feat/phase5-l5-ai-review
git branch -D tmp/l5-03-fullrun
rm -rf apps/api/reports/mutation
```

**`reports/mutation` の削除を忘れない。** ソース全文を含むレポートが残ると、次に走る `l2-gitleaks` がそれを読む（§1.55）。

実測値は Task 8 で findings に書く。この時点ではメモに残す。

---

## Task 4: `verification/run-l5.sh` を作り、3 ケース × 5 回の反復実測を回す

**Files:**
- Create: `verification/run-l5.sh`
- Create: `verification/l5-runs/`（生成物。追跡する）
- Create: `verification/L5-REVIEW.md`（生成物。追跡する）

**Interfaces:**
- Consumes: Task 2 の `scripts/gates/l5-ai-review.sh`（`GATE_BASE_REF` と `L5_REVIEW_OUT` を渡して呼ぶ）、Task 3 の 3 ケース、Task 1 が確定させた出力形式
- Produces: `verification/L5-REVIEW.md`（集計表）と `verification/l5-runs/<CASE-ID>/run-N.md`（生出力 15 本）

- [ ] **Step 1: 判定に使うキーワードを Task 1 の生出力から決める**

`/tmp/l5-probe/after.md`（Task 1 Step 4 の出力）を読み、次を確認する。

- チェックリスト項目がどういう文字列で出力されるか（「境界値」「N+1」がそのまま出るか、言い換えられるか）
- 「該当」「非該当」がどう表現されるか
- 出力が表形式（`| 重大度 | ファイル:行 | 指摘 | 根拠 |`）になっているか

**この観察に基づいて grep パターンを決める。** 観察せずにパターンを書いてはいけない。「該当なし」と書かれた行にもキーワードが出るため、キーワード単独の grep は偽陽性になる（D6 の判断理由）。

- [ ] **Step 2: `run-l5.sh` を書く**

`verification/run-l5.sh`:

```bash
#!/usr/bin/env bash
# L5（AI レビュー）の反復実測。
#
#   verification/run-l5.sh [回数]
#
# L5 系 3 ケースそれぞれについて、同じ差分に対して l5-ai-review を N 回
# （既定 5 回）実行し、生出力を verification/l5-runs/ に保存して
# verification/L5-REVIEW.md に集計する。
#
# なぜ RESULTS.md と別なのか: l5-ai-review は GATE_ORDER にも
# GATE_DETECTION にも入っていない（決定 D1）。claude -p は非決定的で、
# 1 回の結果を RESULTS.md に恒久的な事実として固定すると誤読を生む。
# 手順書 §6.1 自身が「LLM の判定は非頑健」と書いているので、
# 揺れの実測こそが検証結果である。
set -uo pipefail

toplevel=$(git rev-parse --show-toplevel) || exit 2
[ -n "$toplevel" ] || exit 2
cd "$toplevel" || exit 2

RUNS="${1:-5}"
CASES="L5-01-duplicate-logic L5-02-n-plus-one L5-03-missing-boundary-test"
OUT_DIR=verification/l5-runs
REVIEW=verification/L5-REVIEW.md

if [ -n "$(git status --porcelain)" ]; then
  printf 'エラー: 作業ツリーが汚れています。コミットまたは stash してください\n' >&2
  git status --short >&2
  exit 2
fi

BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BASE_BRANCH" = "HEAD" ]; then
  printf 'エラー: detached HEAD では実行できません\n' >&2
  exit 2
fi

# ... 以下、ケースごとに verify ブランチを切って N 回実行する
```

**残りの本体は次の構造で書く。** 各要素の理由をコメントに残すこと。

1. ケースごとに `verify/l5-<CASE-ID>` ブランチを切り、`case.patch` を `git apply --index` して commit する（`run-case.sh` Step 3〜4 と同じ）
2. **5 回のループは 1 つの検証ブランチの中で回す。** ブランチを切り直さない——差分が同一であることが反復実測の前提だからである
3. 各回で `GATE_BASE_REF="$BASE_BRANCH" L5_REVIEW_OUT="$WORK/<CASE-ID>-run-N.md" ./scripts/gates/l5-ai-review.sh` を実行する。**出力先は一旦 `mktemp -d` の下に置く**（検証ブランチ上で追跡ファイルを作ると `git checkout` での復帰が失敗する。§1.32 (2) と同型）
4. ケースが終わったら元ブランチへ戻り、検証ブランチを削除し、**復帰できたかを検査する**（`run-case.sh` の 212 行目と同じガード）
5. 全ケースが終わってから、`$WORK` の生出力を `verification/l5-runs/<CASE-ID>/run-N.md` へコピーする
6. 機械判定して `L5-REVIEW.md` を書く

**`l5-ai-review.sh` が exit 2 を返した回は「指摘なし」ではなく「実行不能」として記録する。** 集計表で `-` と `×` を区別すること。混ぜると、`claude` が落ちていた回が「AI が指摘しなかった」に化ける。

- [ ] **Step 3: 集計表の形を決める**

`L5-REVIEW.md` に出す表:

```markdown
| ケース | 対応するチェックリスト項目 | 該当と判定 | チェックリスト外の指摘 | 偽陽性 | 実行不能 |
|---|---|---|---|---|---|
| L5-01-duplicate-logic | （存在しない） | n/a | 3/5 | 1 | 0 |
| L5-02-n-plus-one | N+1 | 5/5 | 0/5 | 0 | 0 |
| L5-03-missing-boundary-test | 境界値 | 4/5 | 1/5 | 2 | 0 |
```

3 列目・4 列目は機械判定、5 列目（偽陽性）は生出力を読んで人が数える。**冒頭に「この表が保証していること・していないこと」を `RESULTS.md` と同じ体裁で書く。** 最低限、次の 3 つを明記する。

- 機械判定はキーワードの一致であり、指摘の妥当性を見ていない
- `L5-01` の「対応するチェックリスト項目が存在しない」ことは**手順書の穴**である（§10 が L5 に割り当てた落とし穴を §6.2 のチェックリストがカバーしていない）
- n=5 の比率であり、統計的な信頼区間ではない

- [ ] **Step 4: shellcheck を通す**

```bash
shellcheck verification/run-l5.sh
```

期待: 指摘 0。

- [ ] **Step 5: 1 ケース 1 回で動作を確認する**

いきなり 15 回回さない。まず `RUNS=1` 相当で 1 ケースだけ通す。

```bash
chmod +x verification/run-l5.sh
git add verification/run-l5.sh && git commit -m "feat(l5): 反復実測スクリプトを追加"
./verification/run-l5.sh 1
```

タイムアウト 600000。3 ケース × 1 回 = 3 実行になる。

確認すること:

- 元のブランチに戻っている（`git rev-parse --abbrev-ref HEAD`）
- `verify/l5-*` ブランチが残っていない（`git branch --list 'verify/*'`）
- `verification/l5-runs/<CASE-ID>/run-1.md` が 3 つでき、中身が空でない
- `L5-REVIEW.md` が生成されている

- [ ] **Step 6: 後始末の赤確認**

**ハーネスを変更したら退行を確かめる**（Global Constraints）。`run-l5.sh` の後始末が効いていないと、次に `run-case.sh` を回したとき exit 2 になる。

```bash
git status --porcelain    # l5-runs/ と L5-REVIEW.md が未追跡/変更として出るはず
git add verification/l5-runs verification/L5-REVIEW.md
git commit -m "test(l5): 動作確認の 1 回分の実測"
./verification/run-case.sh L1-02-explicit-any
```

期待: `claimVerdict: match`。**exit 2 になったら `run-l5.sh` の後始末に穴がある**ので直す。

- [ ] **Step 7: 本番の 5 回実測を回す**

```bash
./verification/run-l5.sh 5
```

**バックグラウンドで実行する。** 15 実行 × 1 回あたり数十秒〜数分なので、10 分を超える可能性が高い。

- [ ] **Step 8: 偽陽性を数え、集計を仕上げる**

`verification/l5-runs/` の 15 本を読み、健全な箇所への指摘（偽陽性）を数える。手順書 §6.2 の但し書き「gap を探せと指示されたレビュアは、健全な成果物でも何かしら報告しがち」の実測にあたる。

数え方の基準を `L5-REVIEW.md` に明記する。**「そのケースの `case.patch` が触っていない箇所への指摘」を偽陽性と数える**——パッチが触った箇所への指摘は、たとえ的外れでも「差分に反応した」ことになるため区別する。

```bash
git add verification/l5-runs verification/L5-REVIEW.md
git commit -m "test(l5): 3 ケース × 5 回の反復実測を記録する"
```

---

## Task 5: #41 — `gates.test.sh` に Stryker の実起動確認を足す

**Files:**
- Modify: `scripts/gates/gates.test.sh`

**Interfaces:**
- Consumes: `scripts/stryker-diff.sh`（`GATE_BASE_REF` を読む）
- Produces: `gates.test.sh` に 1 件追加。`L4_MUTATE_FILES=(none)` 以外の経路を通る初めての自動チェック

**背景（#41）:** `run-all.sh` の baseline ループは `GATE_BASE_REF` を export しない。したがって `stryker-diff.sh` は既定の `origin/main` を見て、`apps/api/src` に差分が無いので `L4_MUTATE_FILES=(none)` で緑を返す。`gates.test.sh` の既存 3 件も同じ経路である。**結果として、このリポジトリの自動チェックのどれ一つも「Stryker が実際に起動できる」ことを確認していない。**

**baseline 側は変えない。** `run-all.sh` で `GATE_BASE_REF` を export すると baseline が差分ありで Stryker を回すようになり、影響の実測が別途必要になる（#41 の但し書き）。ここでは `gates.test.sh` に確認を足すだけにする。

- [ ] **Step 1: 手で 1 回実行して所要時間と挙動を確かめる**

テストに組み込む前に、どのファイルを触ると速く終わるかを実測する。`orders.controller.ts` は mutant 9 件・関連 spec 無しで **4 分 16 秒**、`orders.service.ts` は mutant 61 件で **2 秒**（§1.33）。`discount.ts` は関連 spec があるので速いはずだが、実測する。

```bash
git checkout -b tmp/l4-selftest-probe
printf '\n// probe\n' >> apps/api/src/discount/discount.ts
git commit -am "tmp: discount.ts に無害な差分"
time GATE_BASE_REF=feat/phase5-l5-ai-review ./scripts/stryker-diff.sh
echo "exit=$?"
git checkout feat/phase5-l5-ai-review
git branch -D tmp/l4-selftest-probe
rm -rf apps/api/reports/mutation
```

期待: `L4_MUTATE_FILES=src/discount/discount.ts` が出力され、Stryker が実際に mutant を実行し、exit 0（スコアが閾値 50 を超える）。

**exit 1 になったら**、そのファイルの差分限定スコアが閾値を下回っている。テストに使うには不適切なので、別のファイル（`auth.guard.ts` 等）で試す。**exit 3 なら** `GATE_BASE_REF` の渡し方が誤っている。

所要時間を控える。**1 分を大きく超えるなら、`gates.test.sh` に入れるかを再検討する**（既存のテストは全体で数十秒で終わる）。その場合は環境変数でオプトインする形（`GATES_TEST_SLOW=1` のときだけ実行）にし、**既定でスキップすることを出力に明示する**——黙って飛ばすと「走らなかった緑」と「走って通った緑」が区別できなくなる（§1.43）。

- [ ] **Step 2: `gates.test.sh` にテストを足す**

`scripts/gates/gates.test.sh` の末尾に追加する。Step 1 で速いと確認できた場合の形:

```bash
# --- L4 が実際に Stryker を起動できることを確認する（申し送り #41） ---
# run-all.sh の baseline も既存のテストも、apps/api/src に差分が無い状態でしか
# stryker-diff.sh を呼んでいない。どちらも L4_MUTATE_FILES=(none) のスキップ経路で
# 緑になるため、**このリポジトリの自動チェックのどれ一つも「Stryker が実際に
# 起動できる」ことを確認していなかった**。ここで初めてその経路を通す。
#
# 一時ブランチを切って無害な差分を 1 つ作り、元ブランチを GATE_BASE_REF に渡す。
_l4_base=$(git rev-parse --abbrev-ref HEAD)
git checkout --quiet -b tmp/gates-test-l4
printf '\n// gates.test.sh が Stryker の実起動を確認するための一時的な差分\n' >> apps/api/src/discount/discount.ts
git commit --quiet -am "tmp: gates.test.sh の L4 実起動確認"
GATE_BASE_REF="$_l4_base" ./scripts/stryker-diff.sh >/tmp/gates-test-l4.log 2>&1
check 'stryker-diff は差分があるとき Stryker を起動して pass' 0 "$?"
grep -q 'L4_MUTATE_FILES=src/discount/discount.ts' /tmp/gates-test-l4.log
check 'stryker-diff はミューテート対象を出力する' 0 "$?"
grep -qE 'Mutation score|mutants' /tmp/gates-test-l4.log
check 'stryker-diff は実際に mutant を実行する' 0 "$?"
git checkout --quiet "$_l4_base"
git branch -D tmp/gates-test-l4 >/dev/null 2>&1
rm -rf apps/api/reports/mutation
```

**3 件に分ける理由:** exit 0 だけを見ると `(none)` のスキップ経路と区別できない。`L4_MUTATE_FILES` の中身と、Stryker が実際に mutant を実行した証跡の両方を見て初めて #41 の穴が塞がる。

**`grep -qE 'Mutation score|mutants'` のパターンは Step 1 の実出力を見て決める。** Stryker の出力に実際に含まれる文字列を使うこと。推測で書かない。

- [ ] **Step 3: 後始末が確実かを確認する**

このテストは一時ブランチを作りコミットする。途中で失敗すると検証ブランチ上に取り残される。**わざと失敗させて確認する**——`GATE_BASE_REF` を存在しない ref にして実行し、`gates.test.sh` の終了後に元のブランチに戻っているかを見る。

```bash
./scripts/gates/gates.test.sh; echo "exit=$?"
git rev-parse --abbrev-ref HEAD    # feat/phase5-l5-ai-review であること
git branch --list 'tmp/*'           # 空であること
git status --porcelain              # 空であること
```

戻っていなければ、`trap` で後始末する形に直す（`run-case.sh` の `cleanup` と同じ）。

- [ ] **Step 4: 全件実行して commit**

```bash
shellcheck scripts/gates/gates.test.sh
./scripts/gates/gates.test.sh
echo "exit=$?"
git add scripts/gates/gates.test.sh
git commit -m "test(l4): gates.test.sh が Stryker の実起動を確認するようにする（申し送り #41）"
```

期待: 全件 pass。件数を控える（Task 8 で findings に記録する）。

---

## Task 6: nightly のローカル実測（Playwright フル / web Stryker 差分限定）

**Files:**
- 変更なし（実測のみ。結果は Task 8 で findings に書く）
- 例外: 実測の結果ゲートやコードの修正が必要になった場合はここで直す

**Interfaces:**
- Consumes: `scripts/gates/l3-e2e-web.sh`（Phase 3 で作成済み・未実行）、`apps/web/stryker.config.json`
- Produces: 2 つの実測結果（Playwright フルの所要時間と結果、web Stryker 差分限定の exit code と挙動）

- [ ] **Step 1: Docker と DB を起動する**

```bash
docker info >/dev/null && echo "docker OK"
pnpm db:up
```

- [ ] **Step 2: Playwright を初めてフル実行する**

`l3-e2e-web.sh` は Phase 3 で作られたが、**一度も実行されていない**（`GATE_ORDER` の外に置き「Phase 5 の nightly 検証で実行する」とコメントに書いたまま）。

```bash
time ./scripts/gates/l3-e2e-web.sh
echo "exit=$?"
```

タイムアウト 600000、バックグラウンド実行。

**ブラウザのインストールが必要な可能性がある。** `gate_require_runnable playwright` は `playwright --version` しか見ないので、ブラウザ本体が無い状態でもガードを通り、テスト実行時に「Executable doesn't exist」で落ちる。その場合は次を実行してから再試行し、**「ゲートのガードがブラウザ本体の不在を検出できない」ことを findings に記録する**（§1.13 の型）。

```bash
pnpm --filter web exec playwright install chromium
```

- [ ] **Step 3: Playwright の赤確認**

緑を確認しただけでは、そのテストが何も見ていない状態と区別できない（Global Constraints）。E2E が実際に落ちることを確認する。

```bash
git checkout -b tmp/e2e-red-check
```

`apps/web/src/features/orders/OrderList.tsx` の合計表示（`<p>合計: {sumDiscountedTotal(orders)} 円</p>`）のラベルを `合計:` から `総額:` に変える。E2E がこの文字列を見ているなら落ちる。

```bash
./scripts/gates/l3-e2e-web.sh; echo "exit=$?"
git checkout feat/phase5-l5-ai-review && git branch -D tmp/e2e-red-check
```

期待: exit 1（`N failed` がログに出て `gate_fail_if_matches` が fail に落とす）。

**exit 0 だったら、E2E がその表示を検証していない。** どこを壊せば落ちるかを `apps/web/e2e/` のテスト内容から特定し、そこを壊して再試行する。**「実際に起こりうる壊し方」で赤くすること**（§1.44 が Vitest で踏んだのと同じ型）。**exit 2 だったら** ログのパターン（`[0-9]+ failed`）が実際の出力と合っていない。

- [ ] **Step 4: web Stryker の差分限定を実測する（#34）**

**仮説:** 手順書 §5.2 の web 設定にある `"vitest": { "related": true }` が jest-runner の `enableFindRelatedTests` と同型なら、**関連テストが 0 件のファイル**を差分限定でミューテートすると error(2) 相当になる（§1.52 が api 側で実測した挙動）。

関連テストが無い web のファイルを選ぶ。`src/main.tsx` は `mutate` から除外されているので使えない。`src/api/client.ts`（対応する `client.test.ts` が存在しない）が候補。

```bash
ls apps/web/src/api/
pnpm --filter web exec stryker run --mutate src/api/client.ts 2>&1 | tail -30
echo "exit=$?"
```

タイムアウト 600000。

記録すること: exit code、`Mutation score`、「関連テストが見つからない」旨の警告の有無、所要時間。

- [ ] **Step 5: 比較対象として、関連テストがあるファイルも回す**

```bash
pnpm --filter web exec stryker run --mutate src/features/orders/orderTotal.ts 2>&1 | tail -30
echo "exit=$?"
```

Step 4 と挙動が違えば #34 の仮説が裏付けられる。同じなら反証される。**どちらでも findings に書く**（否定的結果も結果である。§1.27 の前例がある）。

- [ ] **Step 6: 後始末**

```bash
rm -rf apps/web/reports/mutation apps/web/.stryker-tmp
git status --porcelain    # 空であること
pnpm db:down
```

**`reports/mutation` を必ず消す。** web のレポートも `l2-gitleaks` の走査対象に入る（§1.55 の末尾で予防として削除対象に含めた経路）。

実測結果はメモに残し、Task 8 で findings に書く。

---

## Task 7: `cloudbuild.pr.yaml` と `cloudbuild.nightly.yaml` を作る

**Files:**
- Create: `cloudbuild.pr.yaml`
- Create: `cloudbuild.nightly.yaml`

**Interfaces:**
- Consumes: `scripts/gates/*.sh`（`GATE_BASE_REF` を読む規約）、`scripts/stryker-diff.sh`
- Produces: 2 つの yaml。**実行しない**（`gcloud` が無い）

**方針:** `scripts/gates/*.sh` を呼ぶだけの薄い記述にする。「ローカルで検証したものと CI で動くものが同一」を担保するため（全体設計書 §10）。手順書 §7 は各ステップにコマンドを直書きしているが、そうするとローカルのゲートと CI のゲートが別物になり、この検証で得た実測が CI に転写できない。

- [ ] **Step 1: `cloudbuild.pr.yaml` を書く**

`GATE_ORDER` の 9 本と `GATE_DETECTION` の 1 本、そして L5 を並べる。手順書 §7 の構造（`waitFor` による依存、`substitutions._BASE_BRANCH`、`availableSecrets`）は踏襲する。

各ステップに**手順書 §7 からの逸脱を理由付きでコメントする**。最低限、次の 4 つを書く。

```yaml
# 手順書 §7 からの逸脱 (1): corepack enable を書かない。
#   このリポジトリに corepack が入っていない（申し送り #37(a)）。pnpm は
#   グローバルインストール済みという前提を CI 側にも要求する形になる。
#   手順書をそのまま使う読者は corepack がある前提なので、ここは環境差である。
#
# 手順書 §7 からの逸脱 (2): 各ステップに GATE_BASE_REF を明示的に渡す。
#   stryker-diff.sh と l2-new-deps.sh から git fetch を外したため、比較対象を
#   環境変数で受け取る規約にした（申し送り #37(b)）。渡さないと既定の
#   origin/main を見に行き、shallow clone では解決できず error(2) になる。
#
# 手順書 §7 からの逸脱 (3): l3-test に --filter='...[origin/main]' を使わない。
#   対象 0 件でも exit 0 になり「何が走ったか分からない緑」を作る（§1.43）。
#
# 手順書 §7 からの逸脱 (4): 各ステップがゲートスクリプトを呼ぶ。
#   手順書はコマンドを直書きするが、そうするとローカルで検証したゲートと
#   CI で動くものが別物になる。exit code の 3 値正規化（0/1/2）もゲート
#   スクリプト側にあるので、直書きすると error を fail と誤記録する経路が
#   CI にだけ復活する（設計書 §6.1）。
```

L5 のステップには、**このリポジトリでは `GATE_ORDER` の外に置いた**ことと、その理由（`claude -p` の非決定性。決定 D1）をコメントする。手順書 §7 の `l5-ai-review` ステップ自体は非ブロック（`|| true`）なので、CI 上の位置づけは手順書と同じである。

- [ ] **Step 2: `cloudbuild.nightly.yaml` を書く**

手順書の「nightly（フル実行）」の 3 ステップ（`mutation-full` / `pbt-deep` / `e2e-full`）を書く。次の 3 点をコメントに残す。

```yaml
# (1) ミューテーションレポートを成果物として公開しない。
#   Stryker の json / html レポーターはミューテート対象のソース全文
#   （コメント・リテラル含む）を埋め込む（§1.55）。artifacts に載せると
#   ソースコード全体が公開範囲に入り、秘密が含まれていれば二次的に拡散する。
#   公開するなら保存期間・公開範囲・アクセス制御を先に決めること（申し送り #36）。
#
# (2) baseline スコアとの比較機構は作っていない。
#   incremental を切ったので、手順書 §5.4 の「incremental の誤差をリセット
#   するために nightly でフル実行する」という動機はこのリポジトリでは成立
#   しない。それでもフル実行には価値がある——差分限定では原理的に見えない
#   L4-01 型の低下が見える（§1.56）。ただしその価値は「閾値で止める」ことでは
#   なく「baseline からの低下を見る」ことなので、比較対象のスコアをどこに
#   保存するかを決める必要がある。Phase 5 では決めていない（申し送り #38）。
#
# (3) FC_NUM_RUNS=10000 の対比は実測済みで、期待された差が出ていない。
#   100 回 0.344 秒 / 10000 回 0.350 秒（§1.31）。手順書 §4.5 が暗黙に
#   想定している「nightly は深いぶん遅い」という対比は、検証対象の関数が
#   軽量な純関数である限り成立しない。ステップ自体は手順書どおり残す。
```

- [ ] **Step 3: YAML として妥当であることを確認する**

`gcloud` は無いので構文検査だけ行う。

```bash
node -e "const fs=require('fs');for(const f of ['cloudbuild.pr.yaml','cloudbuild.nightly.yaml']){const s=fs.readFileSync(f,'utf8');if(!s.trim().length)throw new Error(f+' が空');console.log(f, s.split('\n').length, 'lines')}"
```

`js-yaml` はワークスペースの依存に入っている（§1.34）ので、パースできるならそれで確認する。

```bash
node -e "const yaml=require('js-yaml'),fs=require('fs');for(const f of ['cloudbuild.pr.yaml','cloudbuild.nightly.yaml']){const d=yaml.load(fs.readFileSync(f,'utf8'));console.log(f,'steps:',d.steps.length)}"
```

`js-yaml` が解決できない場合はこの検査を飛ばし、**飛ばしたことを Task 8 の記録に書く**（「YAML の妥当性は未検証」と明示する。検証していないものを検証したことにしない）。

- [ ] **Step 4: ゲートが緑のままであることを確認して commit**

追跡ファイルが 2 つ増えるので `l2-gitleaks` の走査対象が増える。

```bash
./scripts/gates/l2-gitleaks.sh; echo "exit=$?"
./scripts/gates/l1-lint.sh; echo "exit=$?"
git add cloudbuild.pr.yaml cloudbuild.nightly.yaml
git commit -m "feat(ci): cloudbuild.pr.yaml と cloudbuild.nightly.yaml を追加（未実行）"
```

---

## Task 8: 全 19 ケースを回し、findings と CLAUDE.md を更新する

**Files:**
- Modify: `verification/RESULTS.md`（生成物）
- Modify: `docs/superpowers/phase0-findings.md`
- Modify: `CLAUDE.md`
- Delete: `docs/superpowers/l5-name-collision.md`（内容を findings §1.61 に取り込んだうえで削除）

**Interfaces:**
- Consumes: Task 1〜7 のすべての実測結果
- Produces: 19 行の `RESULTS.md`、Phase 5 の findings、更新された `CLAUDE.md`

- [ ] **Step 1: Docker を確認して `run-all.sh` を回す**

```bash
docker info >/dev/null && echo "docker OK"
git status --porcelain    # 空であること
./verification/run-all.sh
```

**必ずバックグラウンドで実行する。** 19 ケース + 対照実行。Phase 4 の実測は 16 ケースで 8 分 7 秒だったが、**壁時計は再現しない**（§1.38）ので所要は予測しない。

- [ ] **Step 2: 退行を確認する**

`RESULTS.md` の既存 16 行が Phase 4 と同じ判定であることを確認する。Phase 4 時点は **✅ 10 / ❌ 6 / ⚠️ 0**。

```bash
git diff verification/RESULTS.md
```

**既存行の判定が変わっていたら止まる。** L5 のケース追加やゲート追加が既存ケースに影響した可能性がある（Phase 3 で 4 回、Phase 4 で 2 回起きた層をまたぐ相互作用）。原因を特定してから進む。

L5 系 3 行の判定を控える。予測は `L5-01` / `L5-03` が `❌ どの層も止めなかった`、`L5-02` が `❌ 別の層が止めた`。

- [ ] **Step 3: `RESULTS.md` の注記に L5 の扱いを追記する**

`run-all.sh` が生成する冒頭の「この表が保証していること・していないこと」に、L5 についての項目を足す。**`run-all.sh` の `head.md` を組み立てる `printf` 群を編集する**（`RESULTS.md` を手で編集しない。再生成で消える）。

追記する内容:

```
- **L5（AI レビュー）はこの表に出ない。** `l5-ai-review` は `GATE_ORDER` にも
  `GATE_DETECTION` にも入れていない（`claude -p` は非決定的で、1 回の結果を
  この表に固定すると誤読を生むため）。L5 系 3 ケースの「実際に止めた層」列が
  空になるのはそのためで、AI レビューが指摘しなかったことを意味しない。
  L5 の実測は `verification/L5-REVIEW.md` にある。
```

編集後に `run-all.sh` を再実行すると 19 ケース分をもう一度回すことになる。**注記の追加だけなら、`head.md` の生成部分だけを切り出して確認する**か、Task 8 の最後にまとめて 1 回だけ再実行する。どちらにしたかを記録する。

- [ ] **Step 4: findings に Phase 5 の発見を書く**

`docs/superpowers/phase0-findings.md` の §1 の末尾（現在 §1.60 まで）に追記する。**節番号は 1.61 から連番。** 最低限、次を書く。実測していないことを書かない。

| 節 | 内容 | 出典タスク |
|---|---|---|
| §1.61 | `/code-review` の名前衝突。組み込みと SKILL.md のどちらが呼ばれたか、手順書 §6.2 の指示が空振りするかどうか | Task 1 |
| §1.62 | `L5-01` に対応する §6.2 チェックリスト項目が存在しない（§10 が L5 に割り当てた「設計の一貫性が崩れ、重複が増える」をチェックリストがカバーしていない） | Task 3, 4 |
| §1.63 | 反復実測の結果。同一差分・同一プロンプトで指摘が揺れるか。手順書 §6.1 の「非頑健」主張への実測 | Task 4 |
| §1.64 | 偽陽性の実測。手順書 §6.2 の但し書き「健全な成果物でも何かしら報告しがち」が成り立つか | Task 4 |
| §1.65 | 申し送り #39 が想定した 2 案はどちらも成立しない。`apps/api/src` に N+1 を注入する以上 L4 は構造的に反応し、既存 spec がクエリ形を固定している以上 L3 が先に赤くなる | Task 3 |
| §1.66 | `L5-03` の対照フル実行。境界値テストの欠落がフル実行のスコアにどう出たか（baseline 57.14 %） | Task 3 Step 9 |
| §1.67 | #41 の解消。`gates.test.sh` が初めて Stryker の実起動を確認するようになった | Task 5 |
| §1.68 | Playwright の初実行。所要時間、赤確認の結果、ブラウザ本体の不在をガードが検出できるか | Task 6 |
| §1.69 | web Stryker の差分限定（#34）。仮説が裏付けられたか反証されたか | Task 6 |

**`L5-01` の「対応項目が存在しない」を書くときは、手順書への提案を具体的に 1 つ添える**（§1.26 / §1.32 の書き方に倣う）。例: §6.2 のチェックリストに「重複：同じ業務ルールが 2 箇所以上に実装されていないか」を追加する。

- [ ] **Step 5: §2.2 と §3 の Phase 5 表を更新する**

- §2.2（`L5-02` の申し送り）に **Phase 5 での決定と実測結果**を追記する（§2.1 が Phase 3 で追記した形に倣う）
- §3 の「Phase 5（L5）」の表を「完了済み」に変え、各申し送り（#26 / #27 / #33〜#41）に対応状況の列を足す。**扱わなかったもの（#40 / #27 / #26）は「Phase 6 へ持ち越し」と理由を書く**
- Phase 6 への申し送りを新設する

- [ ] **Step 6: §4 に Phase 5 の受け入れ確認記録を書く**

§4 の末尾に「Phase 5（L5 + L5 系 3 ケース + nightly 実測 + cloudbuild）」を追加する。Phase 4 の記録の体裁に倣い、次を含める。

- 実行したコマンドと出力の要点（`run-all.sh` の結果、`gates.test.sh` の件数、`run-l5.sh` の 15 実行）
- `RESULTS.md` の内訳（✅ / ❌ / ⚠️ の行数と、`claimVerdict` の内訳。**この 2 つは一致しないので両方書く**）
- 「進行中に起きたこと」——踏んだ「緑と守っているは別物」の件数（Phase 1 で 4 件、Phase 2 で 6 件、Phase 3 で 3 + 1 件、Phase 4 で 1 件）

- [ ] **Step 7: `CLAUDE.md` の「現在地」を更新する**

- Phase 5 完了、次は Phase 6（検証レポート作成）
- ゲート本数（`GATE_ORDER` 9 本 + 非ブロック 1 本 + **`GATE_ORDER` 外 2 本**——`l3-e2e-web` と `l5-ai-review`）
- ケース数 19、`RESULTS.md` の内訳
- **L5 系 3 行の ❌ の読み方**を「`RESULTS.md` の ❌ を読むときの注意」に追加する（`L3-03` / `L2-05` と同じ体裁で、「意図した結果であり環境やハーネスの不具合ではない」ことを明記する）
- `verification/L5-REVIEW.md` の存在と役割
- `run-l5.sh` の実行方法と、**追跡ファイルを書き換えるので実行後にコミットが要る**こと

- [ ] **Step 8: 一時ファイルを片付けて最終確認**

```bash
rm -f docs/superpowers/l5-name-collision.md   # 内容は findings §1.61 に移した
git status --porcelain
./scripts/gates/gates.test.sh; echo "gates.test exit=$?"
shellcheck scripts/gates/*.sh scripts/stryker-diff.sh verification/*.sh
```

期待: `gates.test.sh` 全件 pass、shellcheck 指摘 0。

- [ ] **Step 9: commit**

```bash
git add -A
git commit -m "docs: Phase 5 の実測を findings に記録し、CLAUDE.md の現在地を更新する"
```

- [ ] **Step 10: 完了条件を 1 つずつ確認する**

設計書 §6 の 8 項目を上から順に確認し、**それぞれについて「どのコマンドの出力で確認したか」を答えられる状態にする**。

1. `/code-review` の名前衝突の実測結果が findings §1.61 にある
2. L5 系 3 ケースが存在し、`RESULTS.md` が 19 行ある
3. `L5-REVIEW.md` に 3 ケース × 5 回の集計と生出力へのパスがある
4. `gates.test.sh` が Stryker の実起動を確認し、全件 pass する
5. Playwright フルと web Stryker 差分限定の実測結果が findings にある
6. `cloudbuild.pr.yaml` / `cloudbuild.nightly.yaml` が存在し、逸脱に理由がある
7. 既存 16 ケースが Phase 4 から退行していない（✅ 10 / ❌ 6）
8. findings に Phase 5 の受け入れ確認記録がある

**確認できない項目があれば、完了と報告しない。** 何が終わっていないかを明示する。

---

## Self-Review（計画作成時に実施した確認）

**1. Spec coverage**

| spec の節 | 対応タスク |
|---|---|
| §4.1 L5 の実行系（SKILL.md / ゲート / run-l5.sh / L5-REVIEW.md） | 1, 2, 4 |
| §4.2 名前衝突の実測 | 1 |
| §4.3 L5 系 3 ケース | 3 |
| §4.4 判定基準（3 列の集計） | 4 |
| §4.5 #41 の修正 | 5 |
| §4.6 nightly ローカル実測 | 6 |
| §4.7 cloudbuild yaml | 7 |
| §5 未決事項（#40 / #27 / #26） | 8 Step 5 で「Phase 6 へ持ち越し」と記録 |
| §6 完了条件 8 項目 | 8 Step 10 |
| §7 制約 | Global Constraints |

**2. Placeholder scan**

- 「適切なエラー処理を追加」等の曖昧な指示なし
- Task 4 Step 2 の `run-l5.sh` は本体の一部を構造の箇条書きで示している。これは Task 1 の実測結果（出力形式）が確定してからでないと判定ロジックが書けないためで、**Step 1 でその依存を明示している**。書けない理由がある箇所を書けるふりで埋めるほうが有害と判断した
- Task 5 Step 2 の grep パターンと Task 6 Step 4 の対象ファイルは「Step 1 の実出力を見て決める／推測で書かない」と明示している

**3. Type consistency**

- 環境変数名は `GATE_BASE_REF`（既存規約）と `L5_REVIEW_OUT`（新規）の 2 つのみ。Task 2 で定義し Task 4 で消費する形が一致している
- ゲート名は `l5-ai-review` で統一（`layerOfGate` がゲート名の先頭 2 文字から層を導くので `l5-` で始める必要がある。申し送り #21）
- ケース ID は `L5-01-duplicate-logic` / `L5-02-n-plus-one` / `L5-03-missing-boundary-test` で、設計書 §9 の表記と一致
- 生成物のパスは `verification/l5-runs/<CASE-ID>/run-N.md` と `verification/L5-REVIEW.md` で Task 4 と Task 8 で一致
