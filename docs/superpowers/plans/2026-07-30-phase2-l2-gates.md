# Phase 2: L2 ゲート（SAST + 依存関係スキャン）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手順書 §3 の L2（Semgrep / OSV-Scanner / gitleaks / 新規依存検出）をゲートとして実装し、L2 系 5 ケースの判定を完了させ、仮説 1・2・3・5 に結論を出す。

**Architecture:** 3 つのスキャナは Docker で実行し（設計書 §6）、バージョンをダイジェストではなく明示タグで固定する。既存の `scripts/gates/_lib.sh` の exit code 正規化契約（0=pass / 1=fail / 2=error）をそのまま使い、Docker デーモン不在を error に落とすガードを足す。ハーネス側は「非ブロックゲート（`l2-new-deps`）の判定」と「手順書がツール名を名指ししたケースの判定（`claimed_gate`）」の 2 つを新たに扱えるよう拡張する。

**Tech Stack:** semgrep 1.171.0 / osv-scanner 2.4.0 / gitleaks 8.30.1（いずれも Docker）、bash、Node.js の標準テストランナー（`node --test`）

---

## 事前に実測済みの事実

この計画は推測ではなく実測に基づく。**以下は計画作成時に実際に測った値である。** 実装中に食い違ったら、計画ではなく実測を信じ、食い違い自体を `phase0-findings.md` に記録すること。

| # | 対象 | 実測結果 |
|---|---|---|
| M1 | Docker イメージ | `semgrep/semgrep:1.171.0` / `ghcr.io/google/osv-scanner:v2.4.0` / `zricethezav/gitleaks:v8.30.1` がいずれも pull 済み |
| M2 | `pnpm install --frozen-lockfile --ignore-scripts` に架空パッケージ | raw exit **1**、ログに `ERR_PNPM_OUTDATED_LOCKFILE` |
| M3 | `osv-scanner --lockfile=pnpm-lock.yaml`（手順書 §3.3 ② の v1 書式） | v2.4.0 でも**受け付ける**。ただし**パッチ無しのリポジトリで exit 1**（`brace-expansion` 1.1.16 と 2.1.2 が GHSA-mh99-v99m-4gvg、High×2） |
| M4 | `semgrep ci --config p/typescript`（トークン無し） | **exit 0、74 ルールが実際に実行される**。トークンは不要 |
| M5 | `semgrep ci`（`--config` 無し・未ログイン） | **exit 0 で何もしない。**`run 'semgrep login' before using 'semgrep ci' or use 'semgrep scan' and set '--config'` と出しつつ成功扱い |
| M6 | `semgrep ci --config ... --error`（手順書 §3.2 のコマンドそのまま） | **exit 2、`semgrep ci: unknown option '--error'`。手順書のコマンドは実行できない** |
| M7 | `semgrep scan --config p/typescript --config p/nodejs --config p/react --config p/owasp-top-ten --config p/secrets --error` | **パッチ無しで exit 1、findings 3 件**。3 件とも `pnpm-workspace.yaml` に対する供給網設定ルール（`pnpm-trust-policy` / `pnpm-minimum-release-age` / `pnpm-block-exotic-sub-dependencies`、いずれも MEDIUM）。**アプリコードの findings は 0** |
| M8 | `gitleaks detect --no-git --redact --source=...`（手順書 §3.3 ③） | 動作する。ただし `detect` は `gitleaks --help` に載らない非推奨サブコマンド。現行は `gitleaks dir [flags] [path]` |
| M9 | `gitleaks dir --no-git ...` | **exit 126（`unknown flag: --no-git`）**。`--no-git` は `dir` には無い |
| M10 | gitleaks の検出能力 | AWS 公式例示キー `AKIAIOSFODNN7EXAMPLE` は**検出しない**（既定 allowlist）。実在形式の鍵 4 件を置いたディレクトリは `leaks found: 4` / exit 1 |
| M11 | 仮説 5（カスタムルール `nest-controller-without-guard`） | **偽陽性は出ない。正しく発火する。** ガード無し→発火 / `@Controller`→`@UseGuards` の順→発火せず / `@UseGuards`→`@Controller` の順→発火せず。**デコレータ順に非依存** |
| M12 | `pnpm.overrides` を root `package.json` に書く | **無視される**（pnpm 10+ で `pnpm-workspace.yaml` に移動している）。`pnpm-workspace.yaml` の `overrides:` は効く |
| M13 | `overrides: { brace-expansion: 5.0.8 }` 適用後 | lockfile の `brace-expansion` が 5.0.8 のみに集約。**osv exit 0「No issues found」**、`pnpm turbo build typecheck test` 9/9・api 13 tests、`pnpm exec eslint . --max-warnings=0` exit 0 |
| M14 | 架空パッケージ名 `nestjs-order-discount-helper` | npm に**存在しない**（E404） |
| M15 | `dayjs@1.11.21` | 実在。公開は 2026-05-26（`minimumReleaseAge: 10080`＝7 日を満たす） |
| M16 | 手順書 §3.2 の `.semgrep.yml`（`rules: []`）を単独で `--config` に渡す | **exit 0、`Nothing to scan.`**。設定エラーにならないので、これだけでゲートを組むと永久に緑で何も走らない |
| M17 | gitleaks と semgrep を**リポジトリ全体**に当てる | **検証ケースのパッチと設計/計画ドキュメント自身に反応する。** `case.patch` に秘密を書けば gitleaks 2 件 / semgrep 1 件、この計画書に偽キーを書けば gitleaks 4 件 / semgrep 3 件。**対策しないと baseline が赤くなり `run-all.sh` は先頭で止まる** |
| M18 | gitleaks の除外 | `.gitleaks.toml` の**自動検出は効かない**（`--config` の明示が必要）。`File` は `/src/...` の絶対パスなので `^` 固定の相対パス正規表現は一致しない。パス指定の allowlist なら効き、**`apps/` 配下に同じ鍵を置けば exit 1 のまま**（ガードが残る） |
| M19 | semgrep の除外 | `.semgrepignore` に `verification/cases/` と `docs/` を書けば findings が消える。**独自の `.semgrepignore` を置いても `node_modules` は除外されたまま**（走査対象 68 ファイル） |
| M20 | `$queryRawUnsafe` の文字列連結に対する semgrep | **`p/typescript` / `p/nodejs` / `p/react` / `p/owasp-top-ten` / `p/secrets` のいずれも反応しない。** L2-05 は `not-caught` になる見込み |

## Global Constraints

- **`claimed_layer` は絶対に変更してはいけない。** 手順書 §10 の主張そのものであり、これが検証対象である。実測に合わせて書き換えた瞬間に判定が恒真になる。
- **判定を `match` にするために `case.patch` を書き換えてはいけない。** `mismatch` / `not-caught` が出たら、それがこのプロジェクトの成果物である。
- `expect.yml` の `expect` / `expect_detection` は実測に合わせて更新してよい。初回実行で確定させるのが正しい。
- **ゲートを足したら、意図的に違反を 1 つ入れて赤くなることを確認する。** 緑を確認するだけでは、そのゲートが何も見ていない状態と区別できない（`phase0-findings.md` §1.13、Phase 1 で 4 回踏んだ）。**この計画では M5 と M10 という実例が既に 2 つ出ている。**
- ゲートスクリプトは `set -uo pipefail` を使う（`-e` は付けない。非ゼロ exit を捕まえて `gate_finish` に渡すため）。
- **ゲート名は必ず `lN-` で始める。** `judge.mjs` の `layerOfGate` がゲート名の先頭 2 文字から層を導くため（申し送り #21）。
- 依存は完全固定（`^` / `~` を付けない）。Docker イメージも `latest` を使わず明示タグを書く。
- **`corepack enable` を実行しないこと。** `corepack` は入っていない。
- **`gcloud` は入っていない。** `cloudbuild.*.yaml` は Phase 5 の成果物であり、この Phase では作らない。
- コメント・コミットメッセージ・ドキュメントは日本語。

## File Structure

**新規作成**

| ファイル | 責務 |
|---|---|
| `scripts/gates/gates.list.sh` | ゲートの実行順を 1 箇所に定義（申し送り #18）。`run-case.sh` と `run-all.sh` が読む |
| `scripts/gates/l2-osv.sh` | OSV-Scanner ゲート（ブロック） |
| `scripts/gates/l2-gitleaks.sh` | gitleaks ゲート（ブロック） |
| `scripts/gates/l2-semgrep.sh` | Semgrep ゲート（ブロック） |
| `scripts/gates/l2-new-deps.sh` | 新規依存検出（非ブロック。出力で判定） |
| `.gitleaks.toml` | gitleaks の allowlist。検証ケースのパッチと docs を**パスで**除外する（M17 / M18） |
| `.semgrepignore` | semgrep の走査除外。同上（M17 / M19） |
| `.semgrep.yml` | 手順書 §3.2 のルールセット指定ファイル |
| `.semgrep/nestjs.yml` | 手順書 §3.2 の NestJS カスタムルール |
| `verification/cases/L2-01-phantom-package/` | 架空パッケージ |
| `verification/cases/L2-02-guard-missing/` | `@UseGuards` 欠落 |
| `verification/cases/L2-03-hardcoded-secret/` | 秘密のハードコード |
| `verification/cases/L2-04-new-dependency/` | 実在する新規依存 |
| `verification/cases/L2-05-sql-injection/` | `$queryRawUnsafe` の文字列連結 |

**変更**

| ファイル | 変更内容 |
|---|---|
| `pnpm-workspace.yaml` | 供給網設定 3 つ（M7）と `overrides`（M13） |
| `pnpm-lock.yaml` | `overrides` 適用の結果 |
| `scripts/gates/_lib.sh` | `gate_require_docker` とイメージタグ定数を追加 |
| `scripts/gates/l2-install.sh` | fail をログのマーカーで絞る（申し送り #16） |
| `scripts/gates/gates.test.sh` | L2 ゲートの pass / error 経路を追加（申し送り #19）、`TOTAL` の自動計算 |
| `verification/run-case.sh` | ゲート一覧を `gates.list.sh` から読む、非ブロックゲートの実行、`node_modules` の復元（#17）、`GATE_BASE_REF` の export |
| `verification/run-all.sh` | 対照実行を `gates.list.sh` から読む、`claimed_gate` を表に反映 |
| `verification/lib/judge.mjs` | `claimed_gate` と `expect_detection` の判定、TSV 形式の 4 列化 |
| `verification/lib/judge.test.mjs` | 上記のテスト |
| `verification/cases/L1-0*/expect.yml` | 増えた 4 ゲート分の期待値を実測で埋める |
| `verification/RESULTS.md` | `run-all.sh` が生成 |
| `docs/superpowers/phase0-findings.md` | 手順書への修正提案（§1）と Phase 3 への申し送り（§3） |
| `CLAUDE.md` / `README.md` | 現在地とゲート一覧・実行時間の更新 |

---

## Task 1: baseline を緑にする（供給網設定と依存 override）

L2 ゲートを入れる前に、**パッチ無しの状態で L2 が緑であること**を作る。M3 と M7 のとおり、現状のリポジトリは osv も semgrep も赤い。対照実行が赤いままではケースの判定は意味を持たない（`run-all.sh` は先頭で止まる）。

**Files:**
- Modify: `pnpm-workspace.yaml`
- Modify: `pnpm-lock.yaml`（`pnpm install` の結果）

**Interfaces:**
- Consumes: なし
- Produces: `osv-scanner --lockfile=pnpm-lock.yaml` が exit 0、上記 semgrep コマンドが exit 0 になった状態。Task 2〜4 のゲートはこの状態を前提に「クリーンなツリーで pass」を確認する

- [ ] **Step 1: 現状が赤いことを自分の目で確認する**

```bash
docker run --rm -v "$PWD:/src:ro" -w /src ghcr.io/google/osv-scanner:v2.4.0 --lockfile=pnpm-lock.yaml
echo "osv exit=$?"
```

期待: exit 1。`brace-expansion` 1.1.16 / 2.1.2 が GHSA-mh99-v99m-4gvg で挙がる。

```bash
docker run --rm -v "$PWD:/src:ro" -w /src semgrep/semgrep:1.171.0 semgrep scan \
  --config p/typescript --config p/nodejs --config p/react --config p/owasp-top-ten --config p/secrets --error
echo "semgrep exit=$?"
```

期待: exit 1、findings 3 件。3 件とも `pnpm-workspace.yaml:1`。

**この 2 つが赤いことを先に見ておくのが重要である。** 設定を足した後に緑になったとき、「設定が効いた」のか「そもそも何も見ていない」のかを区別できる唯一の材料になる。

- [ ] **Step 2: `pnpm-workspace.yaml` に供給網設定と override を足す**

`pnpm-workspace.yaml` を次の内容にする。

```yaml
packages:
  - 'apps/*'
  - 'packages/*'
allowBuilds:
  '@prisma/client': true
  '@prisma/engines': true
  prisma: true
  unrs-resolver: true

# 供給網対策。semgrep の p/nodejs が要求する 3 つ（実測で findings として挙がった）。
# 手順書 §3.3 は「架空パッケージ・供給網対策」を掲げながら pnpm 側のこれらの設定に
# 触れていない。§1 の修正提案として記録する。
blockExoticSubdeps: true      # 推移的依存を信頼できない配布元から入れさせない
minimumReleaseAge: 10080      # 公開から 7 日（分）経っていない版は入れない
trustPolicy: no-downgrade     # 更新でセキュリティ設定が引き下げられるのを防ぐ

# brace-expansion 1.1.16 / 2.1.2 は GHSA-mh99-v99m-4gvg（High）。いずれも推移的依存で
# 直接指定していない。修正版 5.0.8 は既に lockfile 内に別経路で入っていたので、
# override で 1 本に集約する。
overrides:
  brace-expansion: 5.0.8
```

- [ ] **Step 3: lockfile を更新する**

```bash
pnpm install --no-frozen-lockfile --ignore-scripts
grep -nE "^\s+brace-expansion@" pnpm-lock.yaml
```

期待: `brace-expansion@5.0.8` のみが残る（1.1.16 と 2.1.2 が消える）。

- [ ] **Step 4: 2 つのスキャナが緑になったことを確認する**

```bash
docker run --rm -v "$PWD:/src:ro" -w /src ghcr.io/google/osv-scanner:v2.4.0 --lockfile=pnpm-lock.yaml
echo "osv exit=$?"
```
期待: exit 0、`No issues found`。

```bash
docker run --rm -v "$PWD:/src:ro" -w /src semgrep/semgrep:1.171.0 semgrep scan \
  --config p/typescript --config p/nodejs --config p/react --config p/owasp-top-ten --config p/secrets --error
echo "semgrep exit=$?"
```
期待: exit 0、`Findings: 0`。

- [ ] **Step 5: 既存のゲートが壊れていないことを確認する**

```bash
pnpm turbo build typecheck test
pnpm exec eslint . --max-warnings=0
./scripts/gates/gates.test.sh
```

期待: turbo 9/9（api 13 tests・web 10 tests）、eslint exit 0、gates.test.sh 6 件成功。

`minimumReleaseAge` を入れたので `pnpm install` が新しい版を拒む可能性がある。上の `pnpm install` が成功していれば問題ない。

- [ ] **Step 6: `allowBuilds` の `'@prisma/client': true` が要るかを測る（申し送り #7）**

申し送り #7 は「`turbo` の `generate` 配線後は不要で、その postinstall はスキーマを発見できずスタブを作るだけ」と記録している。ゲートは `--ignore-scripts` を付けるので postinstall はそもそも走らないが、開発時の `pnpm install`（`--ignore-scripts` 無し）では走る。

```bash
cp pnpm-workspace.yaml /tmp/pws-allowbuilds.bak
# allowBuilds から '@prisma/client': true の 1 行だけを削除する
rm -rf node_modules apps/*/node_modules packages/*/node_modules
pnpm install
pnpm turbo build typecheck test
```

**結果を記録すること。** turbo が 9/9 通るなら不要であり、Task 14 で §1 の修正提案（手順書 §1.2 の `pnpm-workspace.yaml` 例に余分な項目がある）として書く。落ちるなら必要なので戻す。

```bash
# 不要と判定した場合はそのまま。必要と判定した場合は戻す
cp /tmp/pws-allowbuilds.bak pnpm-workspace.yaml
pnpm install
```

このステップは白紙リビルドを含むので 5〜10 分かかる。

- [ ] **Step 7: コミット**

```bash
git add pnpm-workspace.yaml pnpm-lock.yaml
git commit -m "chore: 供給網設定と brace-expansion の override で L2 の baseline を緑にする"
```

---

## Task 2: `l2-osv.sh`（OSV-Scanner ゲート）

最初の Docker ゲート。ここで **Docker デーモン不在を error(2) に落とすガード**を作る。設計書 §6.1 が「このハーネス最大の誤判定リスク」と名指しした箇所である。

**Files:**
- Modify: `scripts/gates/_lib.sh`
- Create: `scripts/gates/l2-osv.sh`

**Interfaces:**
- Consumes: `_lib.sh` の `GATE_PASS` / `GATE_FAIL` / `GATE_ERROR` / `gate_require_cmd` / `gate_require_repo` / `gate_finish`
- Produces: `gate_require_docker`（引数なし。Docker が使えなければ exit 2）、定数 `GATE_IMG_SEMGREP` / `GATE_IMG_OSV` / `GATE_IMG_GITLEAKS`。Task 3・4 が使う

- [ ] **Step 1: `_lib.sh` にイメージタグ定数と Docker ガードを足す**

`scripts/gates/_lib.sh` の `GATE_ERROR=2` の直後に足す。

```bash
# Docker イメージは latest を使わず固定する。リポジトリの依存固定方針と同じ理由（再現性）に
# 加えて、ツールの版が変わるとゲートの挙動が黙って変わり、検証結果の意味が失われるため。
GATE_IMG_SEMGREP='semgrep/semgrep:1.171.0'
GATE_IMG_OSV='ghcr.io/google/osv-scanner:v2.4.0'
GATE_IMG_GITLEAKS='zricethezav/gitleaks:v8.30.1'
```

`gate_require_runnable` の直後に足す。

```bash
# Docker が使えることを確認する。使えなければ error で終了する。
#
# 設計書 §6.1 が「このハーネス最大の誤判定リスク」と呼ぶのがここである。
# Docker デーモンが止まっているだけの状態を「ゲートが欠陥を検出した」と記録すると、
# 検証結果そのものが無意味になる。docker コマンドの存在だけでは足りない。
# デーモンが止まっていても docker バイナリは在り、run は非ゼロで落ちる。
gate_require_docker() {
  gate_require_cmd docker
  if ! docker info >/dev/null 2>&1; then
    printf 'gate error: Docker デーモンが起動していません（Docker Desktop を起動してください）\n' >&2
    exit "$GATE_ERROR"
  fi
}
```

- [ ] **Step 2: `l2-osv.sh` を書く**

`scripts/gates/l2-osv.sh` を作る。

```bash
#!/usr/bin/env bash
# L2: 依存ライブラリの既知脆弱性スキャン（手順書 §3.3 ②）
#
# 手順書は `osv-scanner --lockfile=pnpm-lock.yaml` と書く。これは v1 の書式だが、
# 実測では v2.4.0 も受け付ける（設計書 §6 の「v1/v2 で CLI 書式が異なる」への回答）。
# 手順書のコマンドをそのまま検証するのが目的なので、v2 の `scan source -L` ではなく
# 手順書どおりの書式を使う。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_docker

docker run --rm -v "$PWD:/src:ro" -w /src "$GATE_IMG_OSV" --lockfile=pnpm-lock.yaml
# osv-scanner は脆弱性を見つけると 1 を返す。それ以外の非ゼロ（lockfile 不在、
# ネットワーク断、イメージ起動失敗）は error に落とす。
gate_finish "$?" 1
```

```bash
chmod +x scripts/gates/l2-osv.sh
```

- [ ] **Step 3: クリーンなツリーで pass することを確認する**

```bash
./scripts/gates/l2-osv.sh; echo "exit=$?"
```
期待: exit 0。

- [ ] **Step 4: Docker が無いときに error(2) になることを確認する**

```bash
( PATH=/usr/bin:/bin ./scripts/gates/l2-osv.sh ) >/dev/null 2>&1; echo "exit=$?"
```
期待: exit 2。

`PATH=/nonexistent` は使えない。`#!/usr/bin/env bash` の bash 解決ごと壊れ、ゲートが起動する前にシェルが 127 で落ちるため、ゲートの正規化を検証できない（Phase 1 で踏んだ）。

- [ ] **Step 5: 意図的に脆弱な依存を入れて赤くなることを確認する**

**このステップを飛ばしてはいけない。** Step 3 の緑は「ゲートが何も見ていない」状態と区別がつかない。

`pnpm-workspace.yaml` の `overrides` を一時的に外して、Task 1 で消した脆弱性を戻す。

```bash
cp pnpm-workspace.yaml /tmp/pws.bak
# overrides の 2 行（`overrides:` と `  brace-expansion: 5.0.8`）を削除する
pnpm install --no-frozen-lockfile --ignore-scripts
./scripts/gates/l2-osv.sh; echo "exit=$?"
```
期待: **exit 1**。`brace-expansion` の GHSA-mh99-v99m-4gvg が出る。

```bash
cp /tmp/pws.bak pnpm-workspace.yaml
pnpm install --frozen-lockfile --ignore-scripts
git status --porcelain   # 空であること
./scripts/gates/l2-osv.sh; echo "exit=$?"   # 0 に戻ること
```

- [ ] **Step 6: コミット**

```bash
git add scripts/gates/_lib.sh scripts/gates/l2-osv.sh
git commit -m "feat: L2 の OSV-Scanner ゲートと Docker 不在ガードを追加"
```

---

## Task 3: `l2-gitleaks.sh`（秘密混入ゲート）

**Files:**
- Create: `.gitleaks.toml`
- Create: `scripts/gates/l2-gitleaks.sh`

**Interfaces:**
- Consumes: `_lib.sh` の `gate_require_docker` / `GATE_IMG_GITLEAKS` / `gate_finish`（Task 2）
- Produces: `.gitleaks.toml` の allowlist（Task 13 の `L2-03` がこれを前提にする）

手順書 §3.3 ③ は `gitleaks detect --no-git --redact` と書く。M8 のとおり `detect` は 8.30.1 の `--help` に載らない非推奨サブコマンドだが動作する。**手順書のコマンドをそのまま検証するのが目的なので `detect` を使う。** 非推奨であること自体を §1 の修正提案として記録する。

- [ ] **Step 1: 現状が赤いことを自分の目で確認する**

M17 のとおり、**この計画書自身に書いた偽の鍵に gitleaks が反応する**。対策前の状態を先に見ておく。

```bash
docker run --rm -v "$PWD:/src:ro" zricethezav/gitleaks:v8.30.1 detect --no-git --redact --source=/src
echo "exit=$?"
```

期待: **exit 1、`leaks found: 4`**。4 件すべて `docs/superpowers/plans/2026-07-30-phase2-l2-gates.md`。

- [ ] **Step 2: `.gitleaks.toml` を作る**

リポジトリ全体を走査するゲートは、**意図的に秘密らしい文字列を書いたファイル**に必ず反応する。検証ケースのパッチ（Task 13 が作る）と設計/計画ドキュメントがそれである。

```toml
# gitleaks の allowlist。
#
# 検証ケースのパッチと設計/計画ドキュメントは、意図的に秘密らしい文字列を含む。
# これらは「適用前の記述」なので走査しない。
#
# 除外は必ず「パス」で行い、「値」で行わないこと。値で除外すると、L2-03 のパッチを
# 適用して apps/ 配下に同じ文字列が現れたときも除外され、ゲートが空振りする。
# それでは L2-03 が「gitleaks は秘密を検出しなかった」という誤った結果を出す。
[extend]
useDefault = true

[allowlist]
description = "検証ケースのパッチと設計/計画ドキュメントは意図的に秘密らしい文字列を含む"
paths = [
  '''verification/cases/.*\.patch$''',
  '''docs/.*\.md$''',
]
```

**正規表現を `^verification/...` のように先頭固定しないこと。** M18 のとおり gitleaks が照合するパスは `/src/verification/...` の絶対パスなので、先頭固定すると一致せず allowlist が無言で効かなくなる。

- [ ] **Step 3: `l2-gitleaks.sh` を書く**

```bash
#!/usr/bin/env bash
# L2: シークレット混入チェック（手順書 §3.3 ③）
#
# 手順書は `gitleaks detect --no-git --redact` と書く。gitleaks 8.30.1 では `detect` は
# `gitleaks --help` に載らない非推奨サブコマンドで、現行は `gitleaks dir [flags] [path]` だが、
# 手順書のコマンドをそのまま検証するのが目的なので detect を使う。
#
# なお `dir` に `--no-git` を渡すと exit 126（unknown flag）になる。126 は fail に
# 写像してはいけない。書式ミスを「秘密を検出した」と読み違えることになる。
#
# --config を明示するのは、.gitleaks.toml の自動検出が効かないため（実測）。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_docker

docker run --rm -v "$PWD:/src:ro" "$GATE_IMG_GITLEAKS" \
  detect --no-git --redact --source=/src --config /src/.gitleaks.toml
# gitleaks は漏洩を見つけると 1 を返す。書式ミスは 126、その他の異常も非ゼロなので
# error 側に残す。
gate_finish "$?" 1
```

```bash
chmod +x scripts/gates/l2-gitleaks.sh
```

- [ ] **Step 4: クリーンなツリーで pass することを確認する**

```bash
./scripts/gates/l2-gitleaks.sh; echo "exit=$?"
```

期待: exit 0、`no leaks found`。Step 1 で 4 件出ていたものが 0 になる。**Step 1 の 4 件を見ていないと、この 0 が「allowlist が効いた」のか「そもそも走査していない」のか区別できない。**

- [ ] **Step 5: Docker が無いときに error(2) になることを確認する**

```bash
( PATH=/usr/bin:/bin ./scripts/gates/l2-gitleaks.sh ) >/dev/null 2>&1; echo "exit=$?"
```
期待: exit 2。

- [ ] **Step 6: 実在形式の鍵を置いて赤くなることを確認する**

**このステップを飛ばしてはいけない。** M10 のとおり、AWS の公式ドキュメント例示キー `AKIAIOSFODNN7EXAMPLE` は gitleaks の既定 allowlist に入っており**検出されない**。例示キーで確認して緑を見て「gitleaks は動いている」と結論すると誤る。

```bash
cat > /tmp/leakprobe.ts <<'EOF'
export const awsKey = 'AKIA4KJ7SXQZP2WNVTLM';
export const awsSecret = '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';
EOF
cp /tmp/leakprobe.ts apps/api/src/leakprobe.ts
./scripts/gates/l2-gitleaks.sh; echo "exit=$?"
```
期待: **exit 1**、`leaks found: 2`。

**これが `apps/` 配下では allowlist が効かないことの確認である。** ここが exit 0 になったら allowlist が広すぎるので、`paths` の正規表現を見直すこと。

```bash
rm apps/api/src/leakprobe.ts
git status --porcelain   # 空であること
./scripts/gates/l2-gitleaks.sh; echo "exit=$?"   # 0 に戻ること
```

**このステップで使った鍵の形式を記録しておくこと。** Task 13 の `L2-03-hardcoded-secret` で同じ判断が必要になる。

- [ ] **Step 7: コミット**

```bash
git add .gitleaks.toml scripts/gates/l2-gitleaks.sh
git commit -m "feat: L2 の gitleaks ゲートと allowlist を追加"
```

---

## Task 4: `l2-semgrep.sh` と Semgrep 設定

**Files:**
- Create: `.semgrep.yml`
- Create: `.semgrepignore`
- Create: `.semgrep/nestjs.yml`
- Create: `scripts/gates/l2-semgrep.sh`

**Interfaces:**
- Consumes: `_lib.sh` の `gate_require_docker` / `GATE_IMG_SEMGREP` / `gate_finish`（Task 2）
- Produces: カスタムルール ID `nest-controller-without-guard`。Task 12 の `L2-02-guard-missing` がこれを当てにする。`.semgrepignore` の除外（Task 13 の `L2-03` がこれを前提にする）

**仮説 1 の結論をこのタスクで出す。** M4・M5・M6 のとおり、事前の想定（「`semgrep ci` はトークン前提で動かない」）は誤りで、実態はもっと悪い。`semgrep ci` は `--error` を受け付けず（M6）、`--config` 無しなら**何もせず exit 0 を返す**（M5）。ゲートには `semgrep scan` を使う。

- [ ] **Step 1: 手順書のコマンドが動かないことを自分の目で確認する（仮説 1）**

```bash
docker run --rm -v "$PWD:/src:ro" -w /src semgrep/semgrep:1.171.0 semgrep ci \
  --config p/typescript --config p/nodejs --config p/react --config p/owasp-top-ten --config p/secrets --error
echo "exit=$?"
```
期待: exit 2、`semgrep ci: unknown option '--error'`。

```bash
docker run --rm -v "$PWD:/src:ro" -w /src semgrep/semgrep:1.171.0 semgrep ci
echo "exit=$?"
```
期待: **exit 0**。`run 'semgrep login' before using 'semgrep ci' or use 'semgrep scan' and set '--config'` と出るが成功扱い。

**この 2 つの出力をそのまま控えておくこと。** Task 14 で §1 の修正提案に書く一次資料になる。

- [ ] **Step 2: `.semgrep.yml` を作り、手順書の `rules: []` の挙動を確認する**

手順書 §3.2 のとおりに作る。

```yaml
# .semgrep.yml（ルールセットの指定）
rules: []   # カスタムルールはここに追加
```

```bash
docker run --rm -v "$PWD:/src:ro" -w /src semgrep/semgrep:1.171.0 semgrep scan --config .semgrep.yml
echo "exit=$?"
```

期待（実測済み）: **exit 0、`Nothing to scan.`**。設定エラーにはならない。

**つまり手順書 §3.2 に従って `--config .semgrep.yml` だけでゲートを組むと、永久に緑で何も走らないゲートができる。** M5（`semgrep ci` の空振り）と同型の問題であり、§1 の修正提案として記録する。実際のルールセットは CLI 側の `--config p/...` で指定されるので、このファイルは実質何の役割も持っていない。

ファイルは手順書どおりに残す（手順書の記述を検証するのが目的なので削らない）。ゲートでは他の `--config` と併記する。

- [ ] **Step 3: `.semgrep/nestjs.yml` を作る**

手順書 §3.2 のカスタムルールをそのまま書く。

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

- [ ] **Step 4: `.semgrepignore` を作る**

M17 のとおり、semgrep も検証ケースのパッチと計画ドキュメントの偽キーに反応する（`p/secrets` の `detected-aws-access-key-id-value` など）。gitleaks と同じ理由で**パスで除外する**。

```gitignore
# semgrep の走査対象から外すパス。
#
# 検証ケースのパッチと設計/計画ドキュメントは、意図的に秘密らしい文字列や
# 脆弱なコード片を含む。これらは「適用前の記述」なので走査しない。
# パッチを適用したあとの apps/ 配下の実ファイルは走査対象のまま残る。
#
# 独自の .semgrepignore は semgrep の既定を置き換えるが、semgrep は git 追跡
# ファイルのみを走査するので node_modules は除外されたまま（実測: 走査対象 68 ファイル）。
verification/cases/
docs/
```

- [ ] **Step 5: `l2-semgrep.sh` を書く**

```bash
#!/usr/bin/env bash
# L2: SAST（手順書 §3.2）
#
# 手順書は `semgrep ci ... --error` と書くが、実測では動かない:
#   - `semgrep ci` は --error を受け付けない（exit 2 / unknown option）
#   - `semgrep ci` は --config 無し・未ログインだと何もせず exit 0 を返す
# 後者が危険である。ゲートが緑なのに何も見ていない状態になる。
# 設計書 §6 の読み替え（semgrep ci → semgrep scan）に従う。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_docker

docker run --rm -v "$PWD:/src:ro" -w /src "$GATE_IMG_SEMGREP" semgrep scan \
  --config p/typescript \
  --config p/nodejs \
  --config p/react \
  --config p/owasp-top-ten \
  --config p/secrets \
  --config .semgrep/ \
  --error
# semgrep は findings で 1、設定エラー・CLI 誤り・レジストリ到達不能で 2 を返す。
# 2 を fail に写像すると「ルールを取ってこられなかった」が「脆弱性を検出した」になる。
gate_finish "$?" 1
```

```bash
chmod +x scripts/gates/l2-semgrep.sh
```

`--config .semgrep.yml` は上のコマンドには含めない。Step 2 のとおりルールが空で何も足さないため、含めても挙動は変わらないが、含めると「手順書のファイルが効いている」という誤解を生む。**ファイルは手順書どおりに残しつつ、ゲートでは使わない**という形にして、その理由を §1 に書く。

- [ ] **Step 6: クリーンなツリーで pass することを確認する**

```bash
./scripts/gates/l2-semgrep.sh; echo "exit=$?"
```

期待: exit 0、`Findings: 0`。

ここが 1 になる原因は 2 つある。**どちらなのかをログで確かめること。** (a) Task 1 の供給網設定が入っていない → `pnpm-workspace.yaml:1` に 3 件。(b) Step 4 の `.semgrepignore` が効いていない → `docs/superpowers/plans/2026-07-30-phase2-l2-gates.md` に `detected-aws-*` が 3 件。

- [ ] **Step 7: Docker が無いときに error(2) になることを確認する**

```bash
( PATH=/usr/bin:/bin ./scripts/gates/l2-semgrep.sh ) >/dev/null 2>&1; echo "exit=$?"
```
期待: exit 2。

- [ ] **Step 8: カスタムルールが実際に発火することを確認する（仮説 5）**

**このステップを飛ばしてはいけない。** findings 0 は「ルールが正しく除外した」と「ルールが一度も一致しなかった」を区別しない。

`apps/api/src/orders/orders.controller.ts` の `@UseGuards(AuthGuard)` の行を一時的に削除する。

```bash
./scripts/gates/l2-semgrep.sh; echo "exit=$?"
```
期待: **exit 1**。`nest-controller-without-guard` が `orders.controller.ts` に対して発火する。

```bash
git checkout -- apps/api/src/orders/orders.controller.ts
./scripts/gates/l2-semgrep.sh; echo "exit=$?"   # 0 に戻ること
```

M11 のとおり、現在の `@Controller('orders')` → `@UseGuards(AuthGuard)` の順で偽陽性は出ない。手順書の `pattern-not` は `@UseGuards` → `@Controller` の順しか書いていないが、semgrep のデコレータパターンは順序に非依存である。**申し送り #6 が懸念した偽陽性は発生しない。** これが仮説 5 の結論になる。

- [ ] **Step 9: コミット**

```bash
git add .semgrep.yml .semgrepignore .semgrep/ scripts/gates/l2-semgrep.sh
git commit -m "feat: L2 の Semgrep ゲート・カスタムルール・走査除外を追加"
```

---

## Task 5: `l2-new-deps.sh`（非ブロックの新規依存検出）

唯一の非ブロックゲート。exit code ではなく**出力内容**で判定する（設計書 §8.1）。

**Files:**
- Create: `scripts/gates/l2-new-deps.sh`

**Interfaces:**
- Consumes: `_lib.sh` の `gate_require_repo` / `GATE_ERROR`
- Produces: 検出時に標準出力へ `NEW_DEPENDENCY_DETECTED` を出す。exit code は常に 0（実行できない場合のみ 2）。比較対象は環境変数 `GATE_BASE_REF`（未設定なら `origin/main`）。Task 8 の `run-case.sh` がこれを export する

- [ ] **Step 1: 手順書の `git diff` のパススペックが効くか測る**

手順書 §3.3 は `git diff "origin/$_BASE_BRANCH...HEAD" -- '**/package.json'` と書く。git のパススペックは既定で `**` をシェル glob と同じには扱わないので、ルート直下の `package.json` に一致しない可能性がある。**実測すること。**

```bash
# 一時的にルートと apps/api の package.json を両方触って diff の見え方を測る
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("apps/api/package.json","utf8"));j.dependencies["dayjs"]="1.11.21";fs.writeFileSync("apps/api/package.json",JSON.stringify(j,null,2)+"\n")'
echo "--- '**/package.json'"
git diff -- '**/package.json' --name-only
echo "--- ':(glob)**/package.json'"
git diff -- ':(glob)**/package.json' --name-only
echo "--- 'package.json' '*/package.json' '*/*/package.json'"
git diff -- '*package.json' --name-only
git checkout -- apps/api/package.json
```

**どのパススペックがルート直下の `package.json` に一致したかを記録すること。** 手順書のものが一致しないなら §1 の修正提案になる。ゲートには実際に一致した書式を使う。

- [ ] **Step 2: `l2-new-deps.sh` を書く**

以下は Step 1 で `'*package.json'` がルート直下と `apps/*` の両方に一致した場合の形である。別の書式でなければ一致しなかった場合は、`git diff` の `--` 以降をその文字列に差し替える。

```bash
#!/usr/bin/env bash
# L2: 新規依存の検出（手順書 §3.3 の末尾）
#
# 非ブロックゲート。手順書は「検出時はラベルを付けて人間レビューへ回す」と書いており、
# ここで CI を落とすことは意図していない。したがって exit code は常に 0 で、
# 判定材料は標準出力の NEW_DEPENDENCY_DETECTED である（設計書 §8.1）。
# 実行そのものができなかった場合だけ 2 を返す。
#
# 手順書は origin/$_BASE_BRANCH を直に埋め込むが、検証ハーネスは feature ブランチから
# verify/<CASE-ID> を切るため、比較対象を GATE_BASE_REF で受け取れるようにする。
set -uo pipefail

_gate_dir="${BASH_SOURCE[0]%/*}"
[ "$_gate_dir" = "${BASH_SOURCE[0]}" ] && _gate_dir=.
cd "$_gate_dir/../.." || exit 2
# shellcheck source=scripts/gates/_lib.sh
source scripts/gates/_lib.sh

gate_require_repo
gate_require_cmd git

BASE_REF="${GATE_BASE_REF:-origin/main}"
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  printf 'gate error: 比較対象の ref が見つかりません: %s\n' "$BASE_REF" >&2
  exit "$GATE_ERROR"
fi

# 手順書 §3.3 の grep -E '^\+\s+"' をそのまま使う。これは package.json に追加された
# 引用符で始まる行すべてに一致するので、依存の追加だけでなく scripts の追加や
# 版の変更にも反応する。その粗さ自体が検証対象である。
added=$(git diff "$BASE_REF...HEAD" -- '*package.json' | grep -E '^\+\s+"')
if [ -n "$added" ]; then
  printf '%s\n' "$added"
  printf 'NEW_DEPENDENCY_DETECTED\n'
fi
exit "$GATE_PASS"
```

```bash
chmod +x scripts/gates/l2-new-deps.sh
```

- [ ] **Step 3: 差分が無いときに検出しないことを確認する**

```bash
GATE_BASE_REF=HEAD ./scripts/gates/l2-new-deps.sh; echo "exit=$?"
```
期待: exit 0、出力に `NEW_DEPENDENCY_DETECTED` を含まない。

- [ ] **Step 4: 依存を足したときに検出することを確認する**

**このステップを飛ばしてはいけない。** 常に exit 0 を返すゲートなので、Step 3 の緑だけでは「実装が空でも同じ結果」になる。

```bash
git checkout -b tmp-newdeps-probe
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("apps/api/package.json","utf8"));j.dependencies["dayjs"]="1.11.21";fs.writeFileSync("apps/api/package.json",JSON.stringify(j,null,2)+"\n")'
git commit -aqm "probe: 依存を足す"
GATE_BASE_REF=HEAD~1 ./scripts/gates/l2-new-deps.sh; echo "exit=$?"
```
期待: exit 0 かつ出力に `NEW_DEPENDENCY_DETECTED` を含む。

ルート直下の `package.json` にも反応するかを同じブランチで測る。

```bash
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("package.json","utf8"));j.devDependencies["dayjs"]="1.11.21";fs.writeFileSync("package.json",JSON.stringify(j,null,2)+"\n")'
git commit -aqm "probe: ルートにも依存を足す"
GATE_BASE_REF=HEAD~1 ./scripts/gates/l2-new-deps.sh; echo "exit=$?"
```
期待: 出力に `NEW_DEPENDENCY_DETECTED` を含む。**含まないならパススペックがルートに一致していない。** Step 1 に戻ってパススペックを直すこと。

```bash
git checkout -q -   # 元のブランチへ
git branch -D tmp-newdeps-probe
git status --porcelain   # 空であること
```

- [ ] **Step 5: 比較対象が無いときに error(2) になることを確認する**

```bash
GATE_BASE_REF=no-such-ref ./scripts/gates/l2-new-deps.sh >/dev/null 2>&1; echo "exit=$?"
```
期待: exit 2。

- [ ] **Step 6: コミット**

```bash
git add scripts/gates/l2-new-deps.sh
git commit -m "feat: L2 の新規依存検出ゲート（非ブロック）を追加"
```

---

## Task 6: ゲート一覧の共通化と `gates.test.sh` の拡張

申し送り #18（ゲート一覧が 2 箇所にハードコード）と #19（`gates.test.sh` が `l2-install` を一切テストしない）、#23（`shellcheck` 未導入）に対応する。

**Files:**
- Create: `scripts/gates/gates.list.sh`
- Modify: `scripts/gates/gates.test.sh`

**Interfaces:**
- Consumes: Task 2〜5 の 4 ゲート
- Produces: `gates.list.sh` が定義する 2 つの配列。Task 8 の `run-case.sh` と `run-all.sh` が source する
  - `GATE_ORDER=(l2-install l1-typecheck l1-lint l2-semgrep l2-osv l2-gitleaks)` — ブロックするゲート。実行順。`l2-install` は必ず先頭
  - `GATE_DETECTION=(l2-new-deps)` — 非ブロックゲート。exit code ではなく出力で判定する

- [ ] **Step 1: `shellcheck` を入れる**

```bash
brew install shellcheck
shellcheck --version
```

- [ ] **Step 2: `gates.list.sh` を書く**

```bash
#!/usr/bin/env bash
# ゲートの一覧と実行順。run-case.sh と run-all.sh の双方がこれを source する。
#
# ここに寄せる理由は、Phase 1 で一覧が run-case.sh と run-all.sh の 2 箇所に
# ハードコードされ、片方だけ更新される事故が起きうる状態だったため（申し送り #18）。
# 対照実行するゲートとケースで実行するゲートがずれると、対照が取れていないまま
# 判定が出る。

# ブロックするゲート。exit code で判定する（0=pass / 1=fail / 2=error）。
# l2-install は必ず先頭に置くこと。依存が入っていなければ他のゲートは動かず、
# 連鎖失敗を「ゲートが欠陥を検出した」と誤記録することになる（設計書 §8.2）。
GATE_ORDER=(l2-install l1-typecheck l1-lint l2-semgrep l2-osv l2-gitleaks)

# 非ブロックゲート。exit code は常に 0 なので、出力内容で判定する（設計書 §8.1）。
GATE_DETECTION=(l2-new-deps)
```

- [ ] **Step 3: `gates.test.sh` を書き直す**

`TOTAL=6` のハードコードをやめ、実行したチェック数を数える（Phase 1 で見送った Minor）。L2 ゲートの pass 経路と error 経路を追加する。

```bash
#!/usr/bin/env bash
# ゲートスクリプトの exit code 契約を検証する。
# 0 = pass / 1 = fail / 2 = error
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/gates/gates.list.sh
source scripts/gates/gates.list.sh

FAILURES=0
TOTAL=0

check() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    printf 'ok   %s (exit %s)\n' "$label" "$actual"
  else
    printf 'FAIL %s: expected exit %s, got %s\n' "$label" "$expected" "$actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- クリーンなツリーでは全ブロックゲートが pass ---
for gate in "${GATE_ORDER[@]}"; do
  "./scripts/gates/$gate.sh" >/dev/null 2>&1
  check "$gate はクリーンなツリーで pass" 0 "$?"
done

# --- 非ブロックゲートは検出が無ければ pass かつ無出力 ---
out=$(GATE_BASE_REF=HEAD ./scripts/gates/l2-new-deps.sh 2>/dev/null)
check 'l2-new-deps は差分が無いとき pass' 0 "$?"
case "$out" in
  *NEW_DEPENDENCY_DETECTED*) check 'l2-new-deps は差分が無いとき検出しない' 'no-marker' 'marker' ;;
  *) check 'l2-new-deps は差分が無いとき検出しない' 'no-marker' 'no-marker' ;;
esac

# --- 必要なコマンドが無いときは error(2) ---
# PATH から pnpm と docker を外す。どちらも volta / homebrew などルート外に入るので
# /usr/bin:/bin に絞れば消える。一方 env と bash はここに居るので、
# スクリプト自体は起動できてガードまで到達する。
# PATH=/nonexistent は使えない。`#!/usr/bin/env bash` の bash 解決ごと壊れ、
# ゲートが起動する前にシェルが 127 で落ちるため、ゲートの正規化を検証できない。
for gate in "${GATE_ORDER[@]}"; do
  ( PATH=/usr/bin:/bin "./scripts/gates/$gate.sh" ) >/dev/null 2>&1
  check "$gate はツールが無いとき error" 2 "$?"
done

# --- 非ブロックゲートは比較対象が無いとき error(2) ---
( GATE_BASE_REF=no-such-ref ./scripts/gates/l2-new-deps.sh ) >/dev/null 2>&1
check 'l2-new-deps は比較対象が無いとき error' 2 "$?"

# --- どのカレントディレクトリからでも動く ---
# ゲートは自分でリポジトリルートへ移動するので、呼び出し位置に依存しない。
# ハーネスと CI がこれに依存する。
GATE_ABS="$PWD/scripts/gates"
for gate in "${GATE_ORDER[@]}"; do
  ( cd / && "$GATE_ABS/$gate.sh" ) >/dev/null 2>&1
  check "$gate は / から呼んでも pass" 0 "$?"
done

if [ "$FAILURES" -eq 0 ]; then
  printf '\n全 %s 件のチェックが成功しました\n' "$TOTAL"
  exit 0
fi
printf '\n%s / %s 件のチェックが失敗しました\n' "$FAILURES" "$TOTAL"
exit 1
```

- [ ] **Step 4: 実行して全件通ることを確認する**

```bash
./scripts/gates/gates.test.sh
```

期待: **21 件成功**（`GATE_ORDER` 6 本 × 3 経路 = 18、`l2-new-deps` が pass・無検出・error の 3 件）。`FAILURES` が 0 であること、および `l2-install` を含む全ゲートが 3 経路とも測られていることを確認する。

- [ ] **Step 5: shellcheck を全ゲートに通す**

```bash
shellcheck scripts/gates/*.sh verification/*.sh
echo "shellcheck exit=$?"
```

指摘が出たら直す。ただし**挙動を変える修正は慎重に**。`gate_finish "$?"` の `$?` を取り違えると exit code 契約が壊れる。修正後は必ず Step 4 を再実行する。

- [ ] **Step 6: コミット**

```bash
git add scripts/gates/gates.list.sh scripts/gates/gates.test.sh
git commit -m "refactor: ゲート一覧を gates.list.sh に集約し gates.test.sh を L2 まで広げる"
```

---

## Task 7: `l2-install.sh` の fail 絞り込み（申し送り #16）

現状の `l2-install.sh` は `pnpm install` の非ゼロをすべて fail(1) に写像している。lockfile 不整合は確かに fail だが、**レジストリ到達不能・ネットワーク断も同じ 1 になる**。Phase 1 は全ケースが `claimed_layer: L1` だったので誤った ✅ を生まなかったが、L2 を主張するケースを足すと**ネットワーク障害が「✅ 一致」になる**。

**Files:**
- Modify: `scripts/gates/_lib.sh`
- Modify: `scripts/gates/l2-install.sh`

**Interfaces:**
- Consumes: `_lib.sh` の `GATE_FAIL` / `GATE_ERROR`
- Produces: `gate_fail_if_matches <ログのパス> <パターン>` — ログがパターンに一致すれば exit 1、しなければ exit 2

- [ ] **Step 1: `_lib.sh` に判別ヘルパを足す**

`gate_finish` の直後に足す。

```bash
# ツールの非ゼロ終了を「欠陥の検出」と「ツールが実行できなかった」に切り分ける。
#   $1  ログファイルのパス
#   $2  fail と判定する正規表現（grep -E）
# 一致すれば fail(1)、しなければ error(2)。
#
# exit code だけでは切り分けられないツールのために用意する。pnpm は lockfile 不整合も
# レジストリ到達不能も同じ 1 を返すため、後者を fail と記録すると「ネットワークが
# 落ちていた」が「架空パッケージを検出した」になる（申し送り #16）。
gate_fail_if_matches() {
  local log="$1" pattern="$2"
  if grep -qE "$pattern" "$log"; then
    exit "$GATE_FAIL"
  fi
  printf 'gate error: 想定した失敗理由がログに見つかりません（パターン: %s）\n' "$pattern" >&2
  printf '  ツールが実行できなかった可能性があります。ログ全文:\n' >&2
  cat "$log" >&2
  exit "$GATE_ERROR"
}
```

- [ ] **Step 2: `l2-install.sh` を書き直す**

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

# pnpm は lockfile 不整合もネットワーク断も同じ 1 を返す。exit code だけを見て
# fail に写像すると、レジストリに繋がらなかっただけの状態が「架空パッケージを
# 検出した」として ✅ 一致になる。ログの理由コードで切り分ける。
_install_log=$(mktemp)
pnpm install --frozen-lockfile --ignore-scripts 2>&1 | tee "$_install_log"
raw="${PIPESTATUS[0]}"
if [ "$raw" -ne 0 ]; then
  # ERR_PNPM_OUTDATED_LOCKFILE : package.json と lockfile がずれている（架空パッケージの追加など）
  # ERR_PNPM_NO_LOCKFILE       : lockfile が無い
  # ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE : 同上の別表現
  gate_fail_if_matches "$_install_log" \
    'ERR_PNPM_OUTDATED_LOCKFILE|ERR_PNPM_NO_LOCKFILE|ERR_PNPM_FROZEN_LOCKFILE'
fi
rm -f "$_install_log"

gate_require_runnable prisma pnpm --filter api exec prisma --version
pnpm --filter api exec prisma generate
gate_finish "$?" 1
```

- [ ] **Step 3: クリーンなツリーで pass することを確認する**

```bash
./scripts/gates/l2-install.sh; echo "exit=$?"
```
期待: exit 0。

- [ ] **Step 4: lockfile 不整合が fail(1) になることを確認する**

```bash
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("apps/api/package.json","utf8"));j.dependencies["nestjs-order-discount-helper"]="1.0.0";fs.writeFileSync("apps/api/package.json",JSON.stringify(j,null,2)+"\n")'
./scripts/gates/l2-install.sh >/tmp/inst.log 2>&1; echo "exit=$?"
grep -c ERR_PNPM_OUTDATED_LOCKFILE /tmp/inst.log
git checkout -- apps/api/package.json
```
期待: **exit 1**、ログに `ERR_PNPM_OUTDATED_LOCKFILE` が 1 件以上。

- [ ] **Step 5: 想定外の失敗が error(2) になることを確認する**

`gate_fail_if_matches` が本当に切り分けているかを確かめる。一致しないパターンを渡したときに 2 になることを、ヘルパ単体で測る。

```bash
cat > /tmp/gate_split_probe.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/gates/_lib.sh
printf 'ECONNREFUSED registry.npmjs.org\n' > /tmp/probe.log
gate_fail_if_matches /tmp/probe.log 'ERR_PNPM_OUTDATED_LOCKFILE'
EOF
chmod +x /tmp/gate_split_probe.sh
/tmp/gate_split_probe.sh >/dev/null 2>&1; echo "exit=$?"
```
期待: **exit 2**。ネットワーク断らしきログが fail ではなく error になる。

```bash
rm -f /tmp/gate_split_probe.sh /tmp/probe.log
```

- [ ] **Step 6: gates.test.sh が通ることを確認してコミット**

```bash
./scripts/gates/gates.test.sh
shellcheck scripts/gates/_lib.sh scripts/gates/l2-install.sh
git add scripts/gates/_lib.sh scripts/gates/l2-install.sh
git commit -m "fix: l2-install の fail をログの理由コードで絞り、ネットワーク断を error に落とす"
```

---

## Task 8: `run-case.sh` / `run-all.sh` の拡張

**Files:**
- Modify: `verification/run-case.sh`
- Modify: `verification/run-all.sh`

**Interfaces:**
- Consumes: `gates.list.sh` の `GATE_ORDER` / `GATE_DETECTION`（Task 6）、`l2-new-deps.sh` の `GATE_BASE_REF`（Task 5）
- Produces: `actual.tsv` の 4 列形式 — `<ゲート名>\t<exit code>\t<detected>\t<summary>`
  - ブロックゲートの `detected` は `-`
  - 非ブロックゲートの `detected` は `true` / `false`、`exit code` は 0 か 2
  - Task 9 の `judge.mjs` の `parseActual` がこの形式を読む

- [ ] **Step 1: `run-case.sh` を書き直す**

変更点は 4 つ。(a) ゲート一覧を `gates.list.sh` から読む、(b) 非ブロックゲートを実行して検出有無を記録する、(c) `GATE_BASE_REF` を export する、(d) `node_modules` を元ブランチの状態に戻す（申し送り #17）。

`cd "$(git rev-parse --show-toplevel)"` の直後に足す。

```bash
# shellcheck source=scripts/gates/gates.list.sh
source scripts/gates/gates.list.sh
```

`run_gate` を次に置き換える。

```bash
# ゲートを実行する。l2-install は必ず先。依存が無ければ他が動かないため、
# また install 失敗による連鎖失敗を「ゲートが欠陥を検出した」と誤記録しないため。
#
# TSV は 4 列: <ゲート名> <exit code> <detected> <summary>
# summary はタブを含みうるので必ず最後に置く。
run_gate() {
  local gate="$1"
  local log="$LOGS/$gate.log"
  "./scripts/gates/$gate.sh" >"$log" 2>&1
  local code=$?
  local summary
  summary=$(tail -n 1 "$log" | tr -d '\t' | cut -c1-120)
  printf '%s\t%s\t-\t%s\n' "$gate" "$code" "$summary" >>"$ACTUAL"
  return "$code"
}

# 非ブロックゲートを実行する。exit code ではなく出力の marker で判定する
# （設計書 §8.1）。exit 2 は「実行できなかった」なので detected を決めない。
run_detection_gate() {
  local gate="$1"
  local log="$LOGS/$gate.log"
  "./scripts/gates/$gate.sh" >"$log" 2>&1
  local code=$?
  local detected=false
  if grep -q 'NEW_DEPENDENCY_DETECTED' "$log"; then
    detected=true
  fi
  local summary
  summary=$(tail -n 1 "$log" | tr -d '\t' | cut -c1-120)
  printf '%s\t%s\t%s\t%s\n' "$gate" "$code" "$detected" "$summary" >>"$ACTUAL"
}
```

ゲート実行部を次に置き換える。

```bash
# 非ブロックゲートは元ブランチとの差分を見るので、比較対象を渡す。
export GATE_BASE_REF="$BASE_BRANCH"

if ! run_gate "${GATE_ORDER[0]}"; then
  printf '%s が pass しなかったため後続ゲートを打ち切りました\n' "${GATE_ORDER[0]}" >&2
else
  for gate in "${GATE_ORDER[@]:1}"; do
    run_gate "$gate" || true
  done
  for gate in "${GATE_DETECTION[@]}"; do
    run_detection_gate "$gate"
  done
fi
```

`cleanup` を次に置き換える。

```bash
cleanup() {
  git checkout --quiet "$BASE_BRANCH" 2>/dev/null || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
}
```

`cleanup` 呼び出しと復帰の検査の**後**、`trap - EXIT` の**前**に足す。

```bash
# node_modules を元ブランチの状態に戻す。
#
# ゲートは検証ブランチの package.json / pnpm-lock.yaml で pnpm install を走らせるので、
# node_modules は検証ブランチの状態のまま元ブランチへ持ち越される。L2-01 と L2-04 は
# 依存を触るため、戻さないと次のケースが汚染された node_modules の上で走る。
# run-all.sh の対照実行は先頭で 1 回しか取らないのでこれを検出できない（申し送り #17）。
if ! pnpm install --frozen-lockfile --ignore-scripts >"$LOGS/restore.log" 2>&1; then
  printf 'エラー: node_modules を %s の状態へ戻せませんでした\n' "$BASE_BRANCH" >&2
  printf '  復旧: pnpm install --frozen-lockfile\n' >&2
  tail -n 20 "$LOGS/restore.log" >&2
  exit 2
fi
```

- [ ] **Step 2: `run-all.sh` の対照実行を `gates.list.sh` から読むようにする**

`cd "$(git rev-parse --show-toplevel)"` の直後に足す。

```bash
# shellcheck source=scripts/gates/gates.list.sh
source scripts/gates/gates.list.sh
```

対照実行のループを次に置き換える。

```bash
for gate in "${GATE_ORDER[@]}"; do
```

（`l2-install l1-typecheck l1-lint` のハードコードを消す）

- [ ] **Step 3: 既存ケースが従来どおり動くことを確認する**

**ハーネスを変えたら、既に `match` だったケースを再実行して退行していないか確かめる**（Phase 1 で実際に退行させた）。

```bash
git add -A && git commit -qm "wip: ハーネス拡張"
./verification/run-case.sh L1-05-unchecked-index
```

期待: JSON が返り、`claimVerdict` が `"match"`。`blockedBy` に `l1-typecheck` が入る。

この時点では `judge.mjs` はまだ 3 列 TSV を前提にしている。4 列を渡しても `summary` に `-` が先頭に付くだけで、`summary` は `judge()` から参照されないデッドデータなので判定は変わらない（`phase0-findings.md` の Minor 表に記載済み）。**`claimVerdict` が `"match"` 以外になったら、それは判定に効く退行なので Task 9 に進む前に原因を突き止めること。**

- [ ] **Step 4: `node_modules` の復元が効いていることを確認する**

```bash
./verification/run-case.sh L1-05-unchecked-index >/dev/null
git status --porcelain          # 空であること
git branch --list 'verify/*'    # 何も出ないこと
pnpm install --frozen-lockfile --ignore-scripts 2>&1 | tail -2
```
期待: 最後の install が `Already up to date` 相当（＝復元済み）。

- [ ] **Step 5: shellcheck を通してコミット**

```bash
shellcheck verification/run-case.sh verification/run-all.sh
git add verification/run-case.sh verification/run-all.sh
git commit -m "feat: ハーネスをゲート一覧の共通化・非ブロックゲート・node_modules 復元に対応させる"
```

---

## Task 9: `judge.mjs` に `claimed_gate` と `expect_detection` を実装する

**Files:**
- Modify: `verification/lib/judge.mjs`
- Modify: `verification/lib/judge.test.mjs`

**Interfaces:**
- Consumes: `actual.tsv` の 4 列形式（Task 8）
- Produces: `judge()` の返り値に 2 つのフィールドを追加
  - `claimGateVerdict: 'match' | 'mismatch' | 'n/a' | 'inconclusive'` — `claimed_gate` が指定されているとき、そのゲートが実際に fail したか。未指定なら `'n/a'`
  - `detectionMismatches: Array<{gate, expected, actual}>` — `expect_detection` と実測のずれ。`configVerdict` に合流する
  - `parseExpect` の返り値に `claimedGate: string`（未指定なら `''`）

**なぜ `claimed_gate` が要るか。** 手順書は L2-01 について「架空パッケージは OSV-Scanner が止める」と**ツール名を名指しして**主張している。しかし実際に止めるのは `l2-install` の `--frozen-lockfile` である（仮説 3）。どちらも層としては L2 なので、層粒度の照合では **✅ 一致**になり、仮説 3 の反証が表に出ない。設計書 §8.4 の記載例（`❌ OSV は無反応`）は層粒度だけでは表現できない。

**`claimed_layer` は一切変更しない。** `claimed_gate` は追加フィールドであり、`claimed_layer` の不変条件を保ったまま粒度を上げる。

- [ ] **Step 1: 失敗するテストを書く**

`verification/lib/judge.test.mjs` の末尾に足す。

```js
test('claimed_gate が指定され、そのゲートが止めたら claimGateVerdict は match', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: 'l2-osv',
    expect: { 'l2-osv': 'fail' }, expectDetection: {},
  };
  const actual = { 'l2-osv': { code: 1, detected: '-', summary: '' } };
  const r = judge(expected, actual);
  assert.equal(r.claimVerdict, 'match');
  assert.equal(r.claimGateVerdict, 'match');
});

test('claimed_gate が指定され、同じ層の別ゲートが止めたら claimGateVerdict は mismatch', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: 'l2-osv',
    expect: { 'l2-install': 'fail' }, expectDetection: {},
  };
  const actual = { 'l2-install': { code: 1, detected: '-', summary: '' } };
  const r = judge(expected, actual);
  assert.equal(r.claimVerdict, 'match', '層としては L2 が止めているので match');
  assert.equal(r.claimGateVerdict, 'mismatch', '名指しされた l2-osv は止めていない');
});

test('claimed_gate が無ければ claimGateVerdict は n/a', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L1', claimedGate: '',
    expect: { 'l1-lint': 'fail' }, expectDetection: {},
  };
  const actual = { 'l1-lint': { code: 1, detected: '-', summary: '' } };
  assert.equal(judge(expected, actual).claimGateVerdict, 'n/a');
});

test('expect_detection と実測がずれたら configVerdict は mismatch', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: '',
    expect: { 'l1-lint': 'pass' }, expectDetection: { 'l2-new-deps': true },
  };
  const actual = {
    'l1-lint': { code: 0, detected: '-', summary: '' },
    'l2-new-deps': { code: 0, detected: 'false', summary: '' },
  };
  const r = judge(expected, actual);
  assert.equal(r.configVerdict, 'mismatch');
  assert.deepEqual(r.detectionMismatches, [
    { gate: 'l2-new-deps', expected: true, actual: false },
  ]);
});

test('非ブロックゲートは fail しないので blockedBy に入らない', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: '',
    expect: {}, expectDetection: { 'l2-new-deps': true },
  };
  const actual = { 'l2-new-deps': { code: 0, detected: 'true', summary: '' } };
  const r = judge(expected, actual);
  assert.deepEqual(r.blockedBy, []);
  assert.equal(r.claimVerdict, 'not-caught');
});

test('非ブロックゲートが error(2) なら inconclusive', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: '',
    expect: { 'l1-lint': 'pass' }, expectDetection: { 'l2-new-deps': true },
  };
  const actual = {
    'l1-lint': { code: 0, detected: '-', summary: '' },
    'l2-new-deps': { code: 2, detected: 'false', summary: '' },
  };
  assert.equal(judge(expected, actual).claimVerdict, 'inconclusive');
});

test('parseActual は 4 列 TSV を読む', () => {
  const p = mkTmp('a\t1\t-\tsummary with\ttab\nb\t0\ttrue\tok\n');
  const r = parseActual(p);
  assert.deepEqual(r.a, { code: 1, detected: '-', summary: 'summary with\ttab' });
  assert.deepEqual(r.b, { code: 0, detected: 'true', summary: 'ok' });
});

test('claimed_gate の層が claimed_layer と食い違ったら throw', () => {
  const p = mkTmp('id: X\npitfall: p\nclaimed_layer: L2\nclaimed_gate: l1-lint\nexpect:\n  l1-lint: fail\n');
  assert.throws(() => parseExpect(p), /claimed_gate/);
});
```

既存のテストが 3 列 TSV や `detected` 無しの `actual` を使っている場合は、4 列形式に合わせて更新する。`mkTmp` は既存のヘルパを使う。無ければ次を定義する。

```js
function mkTmp(content) {
  const p = join(tmpdir(), `judge-test-${Math.random().toString(36).slice(2)}`);
  writeFileSync(p, content);
  return p;
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
node --test verification/lib/judge.test.mjs
```
期待: FAIL。`claimGateVerdict` が undefined、`parseActual` が 4 列を読めない。

- [ ] **Step 3: `judge.mjs` を実装する**

`parseExpect` の `parsed` 初期値に `claimedGate: ''` を足し、トップレベルキーの分岐に足す。

```js
    else if (key === 'claimed_gate') parsed.claimedGate = value.trim();
```

検証ブロック（`if (!/^L[1-5]$/.test(...))` の並び）に足す。

```js
  // claimed_gate は任意。指定するなら形式を検査し、claimed_layer と矛盾しないことを確かめる。
  // 食い違ったまま通すと「L2 を主張しているのに L1 のゲートを名指ししている」ケースが
  // 静かに mismatch 固定になる。
  if (parsed.claimedGate !== '') {
    if (!/^l[1-5]-[a-z0-9-]+$/.test(parsed.claimedGate)) {
      throw new Error(`expect.yml の claimed_gate が不正です: ${parsed.claimedGate}`);
    }
    if (layerOfGate(parsed.claimedGate) !== parsed.claimedLayer) {
      throw new Error(
        `expect.yml の claimed_gate(${parsed.claimedGate}) の層が claimed_layer(${parsed.claimedLayer}) と一致しません`,
      );
    }
  }
```

`layerOfGate` を `parseExpect` より前へ移動する（現在は下にある）。

`parseActual` を 4 列対応にする。

```js
/** ゲート実行結果の TSV を読む。列は <ゲート名> <exit code> <detected> <summary> */
export function parseActual(path) {
  const actual = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (line.trim() === '') continue;
    const [gate, code, detected, ...rest] = line.split('\t');
    actual[gate] = { code: Number(code), detected, summary: rest.join('\t') };
  }
  return actual;
}
```

`judge()` を書き換える。**非ブロックゲート（`detected` が `-` 以外）を `blockedBy` から除外するのが要点である。** 非ブロックゲートは常に exit 0 なので現状でも入らないが、明示しておかないと将来の変更で静かに混ざる。

```js
export function judge(expected, actual) {
  const entries = Object.entries(actual);
  const isDetectionGate = ([, r]) => r.detected === 'true' || r.detected === 'false';

  const errored = entries
    .filter(([, r]) => r.code !== CODE_PASS && r.code !== CODE_FAIL)
    .map(([gate]) => gate);

  // 非ブロックゲートは exit code で欠陥を主張しない。層の判定から外す。
  const blockedBy = entries
    .filter((e) => !isDetectionGate(e))
    .filter(([, r]) => r.code === CODE_FAIL)
    .map(([gate]) => gate);

  const blockingLayers = [...new Set(blockedBy.map(layerOfGate))];

  if (errored.length > 0) {
    return {
      claimVerdict: 'inconclusive',
      claimGateVerdict: 'inconclusive',
      configVerdict: 'inconclusive',
      errored,
      blockedBy,
      blockingLayers,
      mismatches: [],
      detectionMismatches: [],
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

  // 非ブロックゲートは exit code ではなく出力内容で判定する（設計書 §8.1）。
  const detectionMismatches = [];
  for (const [gate, want] of Object.entries(expected.expectDetection)) {
    const result = actual[gate];
    if (result === undefined) {
      detectionMismatches.push({ gate, expected: want, actual: 'not-run' });
      continue;
    }
    const got = result.detected === 'true';
    if (got !== want) {
      detectionMismatches.push({ gate, expected: want, actual: got });
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

  // 手順書がツール名を名指ししているケースだけ、ゲート粒度でも照合する。
  // 層は一致するが名指しされたツールは無反応、という形を表に出すため。
  let claimGateVerdict;
  if (expected.claimedGate === '') {
    claimGateVerdict = 'n/a';
  } else if (blockedBy.includes(expected.claimedGate)) {
    claimGateVerdict = 'match';
  } else {
    claimGateVerdict = 'mismatch';
  }

  return {
    claimVerdict,
    claimGateVerdict,
    configVerdict:
      mismatches.length === 0 && detectionMismatches.length === 0 ? 'match' : 'mismatch',
    errored,
    blockedBy,
    blockingLayers,
    mismatches,
    detectionMismatches,
  };
}
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
node --test verification/lib/judge.test.mjs
```

期待: **20 件 PASS**（既存 12 件 + 新規 8 件）。既存 12 件のうち `parseActual` や `actual` を直に組むものは 4 列形式・`detected` フィールド付きに更新が必要なので、件数は増えず内容だけが変わる。

- [ ] **Step 5: `run-all.sh` の表生成に `claimed_gate` を反映する**

`node -e` の中を次に置き換える。

```js
const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
let mark;
if (r.claimVerdict === "inconclusive") mark = "⚠️ 判定不能";
else if (r.claimVerdict === "not-caught") mark = "❌ どの層も止めなかった";
else if (r.claimVerdict === "mismatch") mark = "❌ 別の層が止めた";
else if (r.claimGateVerdict === "mismatch") mark = "❌ 層は一致・主張したツールは無反応";
else mark = "✅ 一致";
const blocked = r.blockedBy.length > 0 ? r.blockedBy.join(", ") : "（なし）";
// 手順書がツール名まで名指ししているケースは、その名前も併記する
const claim = r.expected.claimedGate
  ? `${r.expected.claimedLayer} (${r.expected.claimedGate})`
  : r.expected.claimedLayer;
// 設定の回帰（expect と実測のずれ）は本題ではないので注記として添える
const notes = [];
if (r.mismatches.length > 0) {
  notes.push(r.mismatches.map(m => `${m.gate} 期待 ${m.expected} → 実測 ${m.actual}`).join(" / "));
}
if (r.detectionMismatches.length > 0) {
  notes.push(r.detectionMismatches.map(m => `${m.gate} 検出 期待 ${m.expected} → 実測 ${m.actual}`).join(" / "));
}
const note = notes.length > 0 ? " ※設定ずれ: " + notes.join(" / ") : "";
// pitfall や注記に | が入ると Markdown の表が壊れるのでエスケープする
const esc = (s) => String(s).replace(/\|/g, "\\|");
process.stdout.write(`| ${esc(r.expected.id)} | ${esc(r.expected.pitfall)} | ${esc(claim)} | ${esc(blocked)} | ${esc(mark + note)} |\n`);
```

`run-all.sh` のヘッダの「この表が保証していること・していないこと」に足す。

```bash
  printf -- '- **ゲート単位までは見るが、ルール単位は見ていない。** 手順書がツール名を名指ししている\n'
  printf '  ケースは `claimed_gate` で照合するので「層は一致したが名指しされたツールは無反応」を\n'
  printf '  区別できる。ただし同じゲート内でどのルールが落としたかは区別しない。\n'
```

- [ ] **Step 6: 既存ケースで退行していないことを確認してコミット**

```bash
git add -A && git commit -qm "wip"
./verification/run-case.sh L1-05-unchecked-index
./verification/run-case.sh L1-02-explicit-any
```
期待: どちらも `claimVerdict: "match"`、`claimGateVerdict: "n/a"`。

```bash
git add verification/lib/judge.mjs verification/lib/judge.test.mjs verification/run-all.sh
git commit -m "feat: claimed_gate と expect_detection を judge に実装する"
```

---

## Task 10: 既存 L1 系 6 ケースの期待値を更新する

ゲートが 3 本から 7 本に増えたので、既存ケースの `expect` に不足がある。加えて**新しい L2 ゲートが L1 ケースのパッチに反応すると `blockedBy` に L2 が混ざり、`claimVerdict` が退行しうる**。

**Files:**
- Modify: `verification/cases/L1-01-eslint-disable-abuse/expect.yml`
- Modify: `verification/cases/L1-02-explicit-any/expect.yml`
- Modify: `verification/cases/L1-03-floating-promise/expect.yml`
- Modify: `verification/cases/L1-04-unused-disable/expect.yml`
- Modify: `verification/cases/L1-05-unchecked-index/expect.yml`
- Modify: `verification/cases/L1-06-web-imports-api/expect.yml`

**Interfaces:**
- Consumes: Task 8・9 の拡張済みハーネス
- Produces: 6 ケースすべてが Phase 1 と同じ `claimVerdict` を返す状態（L1-01〜L1-05 が `match`、L1-06 が `not-caught`）

- [ ] **Step 1: 6 ケースを実行して実測値を集める**

```bash
for c in L1-01-eslint-disable-abuse L1-02-explicit-any L1-03-floating-promise \
         L1-04-unused-disable L1-05-unchecked-index L1-06-web-imports-api; do
  printf '\n===== %s\n' "$c"
  ./verification/run-case.sh "$c"
done
```

各ケースの JSON から `blockedBy` と `mismatches` を控える。

- [ ] **Step 2: `expect` を実測に合わせて更新する**

**`claimed_layer` は変えない。** 変えてよいのは `expect` だけである（`CLAUDE.md` の「絶対に守ること」）。

各 `expect.yml` を次の形にする。値は Step 1 の実測で埋める。以下は `L1-05-unchecked-index` の例。

```yaml
id: L1-05-unchecked-index
pitfall: 配列添字アクセスの undefined を考慮しない
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: fail
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 3: `claimVerdict` が Phase 1 と同じであることを確認する**

```bash
git add -A && git commit -qm "wip: L1 ケースの期待値更新"
for c in L1-01-eslint-disable-abuse L1-02-explicit-any L1-03-floating-promise \
         L1-04-unused-disable L1-05-unchecked-index L1-06-web-imports-api; do
  printf '%s: ' "$c"
  ./verification/run-case.sh "$c" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s);console.log(r.claimVerdict, r.configVerdict, JSON.stringify(r.blockedBy))})'
done
```

期待:
- `L1-01` 〜 `L1-05`: `match match [...]`（`blockedBy` に L1 のゲートが入る）
- `L1-06`: `not-caught match []`

**`blockedBy` に L2 のゲートが混ざったら、それは退行ではなく発見である。** たとえば `L1-02-explicit-any` に semgrep が反応するなら、`claimVerdict` は `match` のままだが「L1 と L2 の両方が止めた」ことになる。その場合は `expect` を実測に合わせたうえで、**手順書 §10 の層の割り当てが排他的でないという発見**として Task 14 で §1 に記録する。**ケースを書き換えて L2 を黙らせてはいけない。**

- [ ] **Step 4: コミット**

```bash
git add verification/cases/
git commit -m "chore: L1 系 6 ケースの期待値を L2 ゲート追加後の実測に合わせる"
```

---

## Task 11: `L2-01-phantom-package` と `L2-04-new-dependency`

依存を触る 2 ケース。Task 8 の `node_modules` 復元がここで効く。

**Files:**
- Create: `verification/cases/L2-01-phantom-package/case.patch`
- Create: `verification/cases/L2-01-phantom-package/expect.yml`
- Create: `verification/cases/L2-04-new-dependency/case.patch`
- Create: `verification/cases/L2-04-new-dependency/expect.yml`

**Interfaces:**
- Consumes: Task 7 の `l2-install.sh`、Task 5 の `l2-new-deps.sh`、Task 9 の `claimed_gate` / `expect_detection`
- Produces: 仮説 3 の結論に使う実測データ

### パッチの作り方

`case.patch` は手で書かず、実際に編集して `git diff` で出力する。

```bash
mkdir -p verification/cases/<CASE-ID>
# ... ファイルを編集 ...
git diff > verification/cases/<CASE-ID>/case.patch
git checkout -- .
```

**一時ブランチは作らない。** パッチ作成はコミットを伴わないので、追跡ファイルを編集して `git diff` を取り、`git checkout -- .` で戻すだけで足りる。

**ケースを作ったら実行前にコミットする。** `run-case.sh` は作業ツリーがクリーンでなければ exit 2 で中断する。`git status --porcelain` は未追跡ファイルも報告する。

- [ ] **Step 1: `L2-01-phantom-package` のパッチを作る**

架空パッケージを `apps/api/package.json` に足し、実際に import する。**lockfile は更新しない。** それが `--frozen-lockfile` の防御線を試すという趣旨である（仮説 3）。

パッケージ名は `nestjs-order-discount-helper`。npm に存在しないことを確認済み（M14）。

`apps/api/package.json` の `dependencies` に足す。

```json
    "nestjs-order-discount-helper": "1.0.0",
```

`apps/api/src/orders/orders.service.ts` の import に足す（3 行目の `applyDiscount` の import の直後）。

```ts
import { roundToYen } from 'nestjs-order-discount-helper';
```

`toOrderResponse` の `discountedTotal` を書き換える。

```ts
    discountedTotal: roundToYen(applyDiscount(order.unitPrice * order.quantity, order.user.isMember)),
```

```bash
mkdir -p verification/cases/L2-01-phantom-package
git diff > verification/cases/L2-01-phantom-package/case.patch
git checkout -- .
```

パッチの中身を目で確認し、`package.json` の 1 行追加と `orders.service.ts` の 2 箇所の変更だけが入っていることを確かめる。

- [ ] **Step 2: `L2-01` の `expect.yml` を書く**

```yaml
id: L2-01-phantom-package
pitfall: 存在しないパッケージを import する
claimed_layer: L2
# 手順書 §3.3 ② は架空パッケージ対策として OSV-Scanner を名指ししている。
# 仮説 3 は「OSV は脆弱性 DB 照合なので架空パッケージには無反応」と予測する。
claimed_gate: l2-osv
expect:
  l2-install: fail
```

`expect` に `l2-install` しか書かないのは、`run-case.sh` が `l2-install` の失敗で後続を打ち切るためである（設計書 §8.2）。実行されなかったゲートを `expect` に書くと `not-run` として設定ずれ扱いになる。

- [ ] **Step 3: `L2-04-new-dependency` のパッチを作る**

実在する新規依存を足す。`dayjs@1.11.21`（M15。公開は 2026-05-26 なので `minimumReleaseAge: 10080`＝7 日を満たす）。

**lockfile も一緒に更新する。** L2-01 と違い、このケースは「正規の手順で依存を足した」状況を作る。`--frozen-lockfile` で止まってしまうと `l2-new-deps` に到達しない。

```bash
mkdir -p verification/cases/L2-04-new-dependency
pnpm --filter api add dayjs@1.11.21
```

`apps/api/src/orders/orders.service.ts` で実際に使う。**未使用の import は L1 lint で落ちて L2 の判定が濁るので、必ず参照する形にする。** `OrderResponseDto` の形に触らずに済む形を選ぶ（DTO を変えると `l3-openapi-drift` の題材と混ざる）。

import 群の末尾に足す。

```ts
import dayjs from 'dayjs';
```

`OrderWithUser` 型の定義の直前に足す。

```ts
/** 起点時刻の目印（dayjs の利用箇所） */
const EPOCH_STAMP = dayjs(0).toISOString();
```

`OrdersService` のクラス本体の先頭に足す。

```ts
@Injectable()
export class OrdersService {
  /** 起点時刻の目印 */
  readonly epochStamp = EPOCH_STAMP;

  constructor(private readonly prisma: PrismaService) {}
```

L1 が緑であることを先に確かめる。

```bash
./scripts/gates/l1-lint.sh; echo "l1-lint exit=$?"
./scripts/gates/l1-typecheck.sh; echo "l1-typecheck exit=$?"
```

両方 0 であること。0 にならなければ書き方を調整する（**`dayjs` の追加自体は外さないこと**。それがこのケースの本体である）。

```bash
git diff > verification/cases/L2-04-new-dependency/case.patch
git checkout -- .
pnpm install --frozen-lockfile --ignore-scripts
git status --porcelain   # 空であること
```

`git diff` に `pnpm-lock.yaml` の変更が含まれていることを確認すること。含まれていないとパッチ適用後に `--frozen-lockfile` が落ちる。

- [ ] **Step 4: `L2-04` の `expect.yml` を書く**

```yaml
id: L2-04-new-dependency
pitfall: 実在する新規依存を追加する
claimed_layer: L2
# 手順書 §3.3 の末尾は「新規依存の追加は人間承認を必須にする」と述べ、
# 検出のみでブロックしない運用を示している。
claimed_gate: l2-new-deps
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: pass
  l2-osv: pass
  l2-gitleaks: pass
expect_detection:
  l2-new-deps: true
```

- [ ] **Step 5: コミットして 2 ケースを実行する**

```bash
git add verification/cases/L2-01-phantom-package verification/cases/L2-04-new-dependency
git commit -m "test: L2-01（架空パッケージ）と L2-04（新規依存）のケースを追加"
./verification/run-case.sh L2-01-phantom-package
./verification/run-case.sh L2-04-new-dependency
```

- [ ] **Step 6: 実測に合わせて `expect` を更新し、結果を控える**

`configVerdict` が `mismatch` なら `expect` / `expect_detection` を実測に合わせる。**`claimed_layer` と `claimed_gate` は変えない。`case.patch` も変えない。**

期待している姿（仮説 3 が正しければ）:
- `L2-01`: `claimVerdict: "match"`（層は L2）、`claimGateVerdict: "mismatch"`（OSV は無反応）、`blockedBy: ["l2-install"]`
- `L2-04`: `claimVerdict: "not-caught"`（どのブロックゲートも止めない）、`claimGateVerdict: "mismatch"`（`l2-new-deps` は fail しないので `blockedBy` に入らない）

**`L2-04` の `claimGateVerdict` が `mismatch` になるのは想定内である。** `claimed_gate` は「そのゲートが `blockedBy` に入ったか」で判定するが、`l2-new-deps` は非ブロックなので構造上入らない。この形が出たら**`claimed_gate` の設計そのものが非ブロックゲートを扱えていないという発見**であり、Task 14 で §3 の Phase 3 申し送りに記録する。**判定を良く見せるために `claimed_gate` を消してはいけない。**

```bash
git add verification/cases/
git commit -m "chore: L2-01 / L2-04 の期待値を実測に合わせる"
```

---

## Task 12: `L2-02-guard-missing` と `L2-05-sql-injection`

Semgrep が主役の 2 ケース。

**Files:**
- Create: `verification/cases/L2-02-guard-missing/case.patch`
- Create: `verification/cases/L2-02-guard-missing/expect.yml`
- Create: `verification/cases/L2-05-sql-injection/case.patch`
- Create: `verification/cases/L2-05-sql-injection/expect.yml`

**Interfaces:**
- Consumes: Task 4 の `l2-semgrep.sh` とカスタムルール `nest-controller-without-guard`
- Produces: 仮説 5 の結論に使う実測データ

- [ ] **Step 1: `L2-02-guard-missing` のパッチを作る**

`apps/api/src/orders/orders.controller.ts` から `@UseGuards(AuthGuard)` の行を削除し、未使用になる import も削る（L1 lint に落ちて L2 の判定が濁るのを避けるため）。

変更後の先頭:

```ts
import { Body, Controller, Get, Post, Req } from '@nestjs/common';
import { type AuthenticatedRequest } from '../auth/auth.guard';
import { CreateOrderDto } from './dto/create-order.dto';
import type { OrderResponseDto } from './dto/order-response.dto';
import { OrdersService } from './orders.service';

@Controller('orders')
export class OrdersController {
```

```bash
mkdir -p verification/cases/L2-02-guard-missing
git diff > verification/cases/L2-02-guard-missing/case.patch
git checkout -- .
```

- [ ] **Step 2: `L2-02` の `expect.yml` を書く**

```yaml
id: L2-02-guard-missing
pitfall: Controller から認可ガードを外す
claimed_layer: L2
# 手順書 §3.2 が唯一「自社で書け」と言うカスタムルール。仮説 5 の検証対象。
claimed_gate: l2-semgrep
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: fail
  l2-osv: pass
  l2-gitleaks: pass
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 3: `L2-05-sql-injection` のパッチを作る**

`apps/api/src/orders/orders.service.ts` の `findByUser` を `$queryRawUnsafe` の文字列連結に置き換える。

```ts
  /** 指定ユーザーの注文一覧を、会員割引を適用した合計付きで返す */
  async findByUser(userId: string): Promise<OrderResponseDto[]> {
    const orders = await this.prisma.$queryRawUnsafe<OrderWithUser[]>(
      `SELECT o.*, row_to_json(u.*) AS user FROM "Order" o
         JOIN "User" u ON u.id = o."userId"
        WHERE o."userId" = '` + userId + `'
        ORDER BY o."createdAt" DESC`,
    );

    return orders.map(toOrderResponse);
  }
```

```bash
mkdir -p verification/cases/L2-05-sql-injection
git diff > verification/cases/L2-05-sql-injection/case.patch
git checkout -- .
```

- [ ] **Step 4: `L2-05` の `expect.yml` を書く**

```yaml
id: L2-05-sql-injection
pitfall: $queryRawUnsafe で文字列連結して SQL を組み立てる
claimed_layer: L2
claimed_gate: l2-semgrep
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: fail
  l2-osv: pass
  l2-gitleaks: pass
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 5: コミットして 2 ケースを実行する**

```bash
git add verification/cases/L2-02-guard-missing verification/cases/L2-05-sql-injection
git commit -m "test: L2-02（ガード欠落）と L2-05（SQL インジェクション）のケースを追加"
./verification/run-case.sh L2-02-guard-missing
./verification/run-case.sh L2-05-sql-injection
```

- [ ] **Step 6: 実測に合わせて `expect` を更新し、結果を控える**

**`L2-05` で semgrep は反応しない見込みである（M20）。** 計画作成時に `$queryRawUnsafe` の文字列連結を含むファイルを 5 つのルールセット全部にかけたが、findings は 0 だった。したがって次の手順は「例外処理」ではなく**想定される本筋**である。

1. `expect` の `l2-semgrep` を `pass` に直す（**`claimed_layer` と `claimed_gate` と `case.patch` は変えない**）
2. `claimVerdict` は `not-caught` か、L1 が反応していれば `mismatch` になる
3. **それがこのプロジェクトの成果物である。** 手順書 §3.2 のルールセット選定では SQL インジェクションを拾えないという発見として Task 14 で §1 に記録する

同様に `L2-02` で L1 が先に落ちる可能性もある（`AuthenticatedRequest` の import が未使用になるなど）。その場合は `blockedBy` に `l1-lint` が入り `claimVerdict` が `mismatch` になる。**Step 1 のパッチで未使用 import を削っているのはこれを避けるためだが、それでも落ちるなら実測を優先する。**

```bash
git add verification/cases/
git commit -m "chore: L2-02 / L2-05 の期待値を実測に合わせる"
```

---

## Task 13: `L2-03-hardcoded-secret`

**Files:**
- Create: `verification/cases/L2-03-hardcoded-secret/case.patch`
- Create: `verification/cases/L2-03-hardcoded-secret/expect.yml`

**Interfaces:**
- Consumes: Task 3 の `l2-gitleaks.sh`、Task 4 の `l2-semgrep.sh`（`p/secrets`）
- Produces: gitleaks と semgrep のどちらが（あるいは両方が）秘密を捕まえるかの実測データ

- [ ] **Step 1: パッチを作る**

**AWS の公式ドキュメント例示キー `AKIAIOSFODNN7EXAMPLE` は使わないこと。** M10 のとおり gitleaks の既定 allowlist に入っており検出されない。それを使うと「gitleaks は秘密を検出しない」という誤った結論になる。

`apps/api/src/orders/orders.service.ts` の import 群の直後に足す。

```ts
// 外部の決済プロバイダに送る API キー（本来は環境変数から読むべきもの）
const PAYMENT_API_KEY = 'AKIA4KJ7SXQZP2WNVTLM';
const PAYMENT_API_SECRET = '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';
```

未使用定数は L1 lint に落ちうるので、`OrdersService` から実際に参照する。**`private` にしない。** 参照されない `private` フィールドは `noUnusedLocals` や typescript-eslint に拾われうるので、public な `readonly` にしておく。

```ts
@Injectable()
export class OrdersService {
  /** 決済プロバイダの資格情報 */
  readonly paymentAuth = `${PAYMENT_API_KEY}:${PAYMENT_API_SECRET}`;

  constructor(private readonly prisma: PrismaService) {}
```

**L1 が先に落ちたら L2 の判定が濁るので、パッチを作ったら先に L1 を単体で確かめること。**

```bash
mkdir -p verification/cases/L2-03-hardcoded-secret
# 上記の編集を加える
./scripts/gates/l1-lint.sh; echo "l1-lint exit=$?"
./scripts/gates/l1-typecheck.sh; echo "l1-typecheck exit=$?"
```

両方 0 になるまで書き方を調整する。**秘密の文字列そのものは変えないこと。** 変えると gitleaks の検出可否が変わる。

```bash
git diff > verification/cases/L2-03-hardcoded-secret/case.patch
git checkout -- .
```

- [ ] **Step 2: `expect.yml` を書く**

```yaml
id: L2-03-hardcoded-secret
pitfall: API キーらしき文字列をハードコードする
claimed_layer: L2
# 手順書は §3.2 の p/secrets と §3.3 ③ の gitleaks の 2 経路を用意している。
# どちらか一方でも捕まえれば層としては一致する。ツール名は名指しされていないので
# claimed_gate は書かない。
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: pass
  l2-semgrep: fail
  l2-osv: pass
  l2-gitleaks: fail
expect_detection:
  l2-new-deps: false
```

- [ ] **Step 3: コミットして実行する**

```bash
git add verification/cases/L2-03-hardcoded-secret
git commit -m "test: L2-03（秘密のハードコード）のケースを追加"
./verification/run-case.sh L2-03-hardcoded-secret
```

- [ ] **Step 4: 実測に合わせて `expect` を更新する**

semgrep と gitleaks の片方だけが反応する可能性が高い。**どちらが反応したかを控えること。** 手順書は 2 経路を用意しているので、片方が空振りしていることは §1 の修正提案になる。

```bash
git add verification/cases/
git commit -m "chore: L2-03 の期待値を実測に合わせる"
```

---

## Task 14: 全ケース実行、`RESULTS.md` 生成、発見の記録

**Files:**
- Modify: `verification/RESULTS.md`（`run-all.sh` が生成）
- Modify: `docs/superpowers/phase0-findings.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1〜13 のすべて
- Produces: Phase 2 の完了条件（設計書 §10）— L2 が緑、L2 系 5 ケースの判定完了、仮説 1・2・3・5 に結論

- [ ] **Step 1: 全ケースを実行する**

```bash
git status --porcelain   # 空であること
./verification/run-all.sh 2>&1 | tail -40
```

11 ケース × 7 ゲートなので **30〜45 分**かかる見込み。対照実行が赤いとその場で止まる。止まったら Task 1 に戻る。

- [ ] **Step 2: `RESULTS.md` を確認してコミットする**

`run-all.sh` は追跡ファイルである `RESULTS.md` を書き換える。コミットしないと次回は全行が「⚠️ 実行不能」になる。

```bash
cat verification/RESULTS.md
git add verification/RESULTS.md
git commit -m "docs: L1/L2 全 11 ケースの検証結果を記録"
```

**❌ や ⚠️ の行があってもそのまま残す。** それがこのプロジェクトの成果物である。

- [ ] **Step 3: 仮説 1・2・3・5 の結論を `phase0-findings.md` §1 に書く**

Phase 2 の完了条件はこの 4 つに結論を出すことである（設計書 §10）。既存の §1.14 の後に §1.15 から続ける。

書くべき内容（実測は Task 1〜13 で控えたものを使う）:

| 仮説 | 実測に基づく結論 |
|---|---|
| 1 | 「`semgrep ci` はトークン前提で動かない」という予測は**外れ**。`--config` を明示すればトークン無しで動く。しかし実態はもっと悪い: (a) 手順書 §3.2 のコマンドは `semgrep ci` に `--error` を渡しており **exit 2 で実行できない**、(b) `--config` を外すと**何もせず exit 0 を返す**。ゲートが緑なのに何も見ていない状態が既定で作れてしまう |
| 2 | Phase 0 で結論済み（§1.1 / §1.3）。Phase 2 では `--ignore-scripts` 併用下でも `prisma generate` を明示すれば通ることを対照実行で再確認した |
| 3 | 架空パッケージを止めたのは **`--frozen-lockfile`（`l2-install`）**であり、OSV-Scanner は無反応。手順書 §3.3 ② の位置づけを「架空パッケージ対策」から「既知脆弱性対策」に限定すべき |
| 5 | カスタムルール `nest-controller-without-guard` は**期待どおり動く**。申し送り #6 が懸念したデコレータ順による偽陽性は**発生しない**（`@Controller`→`@UseGuards` の順でも `pattern-not` が効く）。手順書の記述は正しい |

加えて、Phase 2 で新しく見つかった手順書への修正提案を書く。少なくとも次を含める（実測で確認できたものだけ）:

- **`semgrep ci` は `--error` を受け付けず、`--config` 無しなら空振りする**（M5 / M6）
- **手順書 §3.2 の `.semgrep.yml`（`rules: []`）は単独では何も走らせない**（M16）。設定エラーにならず exit 0 を返すので、これをゲートにすると永久に緑になる。実際のルールセットは CLI の `--config p/...` 側にあり、このファイルは役割を持っていない
- **`pnpm-workspace.yaml` の `allowBuilds` の `'@prisma/client': true`**（Task 1 Step 6 の実測結果を書く）
- **「ゲートが緑」と「ゲートが守っている」は別物である（Phase 2 で 4 回観測）。** §1.13 の表に Phase 2 の 4 件を追記する: (a) `semgrep ci` が `--config` 無しで exit 0（M5）、(b) `.semgrep.yml` の `rules: []` が exit 0 で何も走らせない（M16）、(c) gitleaks が AWS 公式例示キーを検出しない（M10）、(d) 偽陽性を値ベースの allowlist で黙らせると、欠陥を仕込んだあとも黙るので秘密検出ゲートが空振りする（Task 3 Step 2 / Step 6）。**いずれも「手順書のとおりに導入して緑を確認する」だけでは気づけない**
- **`osv-scanner --lockfile=` をゲートにすると、直接指定していない推移的依存の脆弱性で赤くなる。** 手順書 §3.3 ② は抑制手段（`overrides` や `osv-scanner.toml`）にも、その運用負荷にも触れていない
- **手順書 §3.3 は pnpm 側の供給網設定（`blockExoticSubdeps` / `minimumReleaseAge` / `trustPolicy`）に触れていない。** semgrep の `p/nodejs` はこれらを ERROR ではなく MEDIUM で要求してくる
- **`gitleaks detect` は 8.30.1 で非推奨**（`--help` に載らない）。現行は `gitleaks dir`。ただし `dir` に `--no-git` を渡すと exit 126 になる
- **gitleaks は AWS 公式例示キーを検出しない。** 手順書に従って導入したことを例示キーで確認すると、空振りしているゲートを緑と誤認する
- **手順書 §3.3 ③ の `gitleaks detect --no-git` はリポジトリ全体を走査するため、ドキュメントや検証用フィクスチャに例示鍵を書くと赤くなる**（M17）。手順書は抑制手段（`.gitleaks.toml` の allowlist）にも、その運用が必要になることにも触れていない。同じ問題が `p/secrets` を含む semgrep にも起きる。**除外は必ずパスで行い値で行わないこと**（値で除外すると欠陥を仕込んだあとも除外され、ゲートが空振りする）も手順書に無い注意点である
- **`.gitleaks.toml` の自動検出は効かない**（M18）。`--config` の明示が必要で、照合パスは `--source` を起点とした絶対パスになる
- **手順書 §3.2 のルールセット選定では SQL インジェクション（`$queryRawUnsafe` の文字列連結）を拾えない**（M20）。5 つのルールセット全部にかけて findings 0。§3.2 が「認可は SAST が最も苦手」とだけ注意しているが、実測では生 SQL の組み立ても拾えていない
- **手順書 §3.3 の `git diff -- '**/package.json'` のパススペック**（Task 5 Step 1 の実測結果を書く）
- **手順書 §3.3 の `grep -E '^\+\s+"'` は依存の追加以外にも反応する**（scripts の追加、版の変更）
- Task 10 Step 3 で L2 ゲートが L1 ケースに反応した場合は、**手順書 §10 の層の割り当てが排他的でない**という発見として書く

- [ ] **Step 4: Phase 3 への申し送りを `phase0-findings.md` §3 に書く**

少なくとも次を含める:

- **`claimed_gate` は非ブロックゲートを扱えない。** `blockedBy` は fail したゲートの集合なので、常に exit 0 の `l2-new-deps` は構造上そこに入らない。`L2-04` の `claimGateVerdict` が `mismatch` 固定になる（Task 11 Step 6）。Phase 3 以降で非ブロックゲート用の照合を足すか、`claimed_gate` を非ブロックゲートに使わない規約にするかを決める
- **`run-all.sh` の所要時間が 30〜45 分に伸びた。** ケースが 19 本に増える Phase 5 では 1 時間を超える。semgrep のレジストリ取得をキャッシュするなどの検討が要る
- **申し送り #20（ルール ID 照合）は未解決のまま。** `claimed_gate` でゲート粒度までは上がったが、同じゲート内でどのルールが落としたかは依然として見ていない
- **申し送り #8（`prisma generate` が `DATABASE_URL` 未設定でどう振る舞うか）は未着手。** `cloudbuild.*.yaml` を作る Phase 5 で env の受け渡しとして扱う
- Phase 1 の申し送り #6〜8 / #16〜23 のうち、Phase 2 で解消したもの・残したものを明記する。Phase 2 で解消したのは #6（仮説 5、Task 4）・#7（Task 1）・#16（Task 7）・#17（Task 8）・#18（Task 6）・#19（Task 6）・#23（Task 6）

- [ ] **Step 5: `CLAUDE.md` と `README.md` を更新する**

`CLAUDE.md`:
- 「現在地」を Phase 2 完了に更新し、L2 系 5 ケースの結果を 1 行で書く
- 「環境」に **Docker が必須であること**と、3 つのイメージのタグを足す
- 検証の実行時間を実測に合わせる（`run-all.sh` が 15〜25 分 → 実測値）

`README.md`:
- 検証セクションのゲート一覧に L2 の 4 本を足す
- Docker Desktop の起動が前提であることを書く

- [ ] **Step 6: 最終確認**

```bash
./scripts/gates/gates.test.sh
node --test verification/lib/judge.test.mjs
shellcheck scripts/gates/*.sh verification/*.sh
pnpm turbo build typecheck test
pnpm exec eslint . --max-warnings=0
git status --porcelain          # 空であること
git branch --list 'verify/*'    # 何も出ないこと
```

すべて成功することを確認する。**実際にコマンドを実行して出力を見てから完了と言うこと。** 実行せずに「通るはず」と書かない。

- [ ] **Step 7: コミット**

```bash
git add docs/superpowers/phase0-findings.md CLAUDE.md README.md
git commit -m "docs: Phase 2 の発見（仮説 1・2・3・5 の結論）と Phase 3 への申し送りを記録"
```

---

## Phase 2 の完了条件（設計書 §10）

| 条件 | 確認方法 |
|---|---|
| L2 が緑 | `./scripts/gates/gates.test.sh` が全件成功。`run-all.sh` の対照実行が通る |
| L2 系 5 ケースの判定完了 | `verification/RESULTS.md` に L2-01〜L2-05 の 5 行がある |
| 仮説 1 に結論 | `phase0-findings.md` §1 に記載 |
| 仮説 2 に結論 | `phase0-findings.md` §1 に記載 |
| 仮説 3 に結論 | `phase0-findings.md` §1 に記載 |
| 仮説 5 に結論 | `phase0-findings.md` §1 に記載 |
| 既存 L1 系 6 ケースが退行していない | `RESULTS.md` の L1 行が Phase 1 と同じ判定 |
