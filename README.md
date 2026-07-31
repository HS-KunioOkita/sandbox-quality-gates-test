# sandbox-quality-gates-test

多層品質ゲート L1〜L5 の検証用サンドボックス。

- 導入手順書: `docs/多層品質ゲート_L1-L5_導入手順_NestJS-React.md`
- 検証環境の設計: `docs/superpowers/specs/2026-07-29-multilayer-quality-gates-verification-design.md`

## 必要なもの

- Node.js 24 系
- pnpm 11 系
- **Docker Desktop（起動していること）** — PostgreSQL に加えて、L2 のゲート 3 本（Semgrep・OSV-Scanner・gitleaks）がコンテナで動く。起動していないとこれらのゲートは exit 2（ツールが実行できなかった）で止まる
- shellcheck（ゲートスクリプトを検査する場合のみ）

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

アプリのビルド・型チェック・テスト:

```bash
pnpm turbo build typecheck test
```

品質ゲート:

```bash
pnpm lint                        # eslint . --max-warnings=0
./scripts/gates/gates.test.sh    # 全ゲートの exit code 契約を検証（Docker 必須）
```

ゲートは `scripts/gates/` にある。exit code は `0`=pass / `1`=fail（欠陥を検出）/ `2`=error（ツールが実行できなかった）。

| ゲート | 中身 | Docker |
|---|---|---|
| `l2-install` | `pnpm install --frozen-lockfile --ignore-scripts` + `prisma generate` | 不要 |
| `l1-typecheck` | `pnpm turbo typecheck` | 不要 |
| `l1-lint` | `pnpm exec eslint . --max-warnings=0` | 不要 |
| `l2-semgrep` | `semgrep scan`（レジストリの 5 セット + `.semgrep/nestjs.yml` のカスタムルール） | **必要** |
| `l2-osv` | `osv-scanner --lockfile=pnpm-lock.yaml` | **必要** |
| `l2-gitleaks` | `gitleaks detect --redact`（`.gitleaks.toml` を `--config` で明示） | **必要** |
| `l2-new-deps` | 新規依存の検出。**非ブロック**（常に exit 0、出力のマーカーで伝える） | 不要 |

実行順と一覧は `scripts/gates/gates.list.sh` に集約してある。

手順書の主張に対する検証（意図的な欠陥を注入してゲートに当てる）:

```bash
./verification/run-case.sh <CASE-ID>   # 1 ケース（約 3 分）
./verification/run-all.sh              # 全ケース + 対照実行（実測 約 40 分）
```

`run-all.sh` は `verification/RESULTS.md` を生成する。作業ツリーがクリーンでないと中断するので、ケースを追加したらコミットしてから実行すること。実行後は `RESULTS.md` の差分をコミットするか `git checkout` で戻す。

検証結果と手順書への修正提案は [`docs/superpowers/phase0-findings.md`](docs/superpowers/phase0-findings.md) にまとめてある。
