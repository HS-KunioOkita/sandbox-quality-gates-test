// 手順書 §4.2 のコードをそのまま置くと、DATABASE_URL の差し替えまでしか行われず
// 空の DB に接続することになる。実測（仮説 8）で
// 「The table `public.Order` does not exist in the current database.」を確認済み
// （phase0-findings.md §1.29 に引用）。マイグレーション適用を追加して直す。
import { execFileSync } from 'node:child_process';
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';

// beforeAll が start() 以前に失敗した場合に afterAll の container?.stop() が
// 意味を持つよう、型は undefined を許容しておく（非 optional だと
// no-unnecessary-condition に引っかかる）。
let container: StartedPostgreSqlContainer | undefined;

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16-alpine').start();
  const url = container.getConnectionUri();
  process.env.DATABASE_URL = url;

  // 手順書 §4.2 に無い一手（仮説 8）。DATABASE_URL の差し替えだけでは
  // テーブルが 1 つも無い DB に接続することになる。
  //
  // env に DATABASE_URL を明示的に渡す理由: Prisma CLI はリポジトリルートの
  // .env を読むが、既に process.env にある値は上書きしない。ここで渡さないと
  // 「.env のローカル DB に向けてマイグレーションを適用してしまう」——つまり
  // テストがコンテナではなく開発用 DB を壊す事故になる。
  //
  // migrate dev ではなく deploy を使う。dev は対話的でシャドー DB を作る。
  execFileSync('pnpm', ['exec', 'prisma', 'migrate', 'deploy'], {
    cwd: `${__dirname}/..`,
    env: { ...process.env, DATABASE_URL: url },
    stdio: 'inherit',
  });
}, 120_000);

afterAll(async () => {
  await container?.stop();
});
