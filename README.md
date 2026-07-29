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
