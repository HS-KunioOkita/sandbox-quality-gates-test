import { defineConfig } from '@playwright/test';

// 手順書 §4.1 は「主要導線のみ」とだけ書き、E2E がアプリと DB をどう起こすかに
// 触れていない。ここでは webServer で API と Vite を起こし、DB は
// docker compose（pnpm db:up）で先に立っている前提にする。
export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  use: { baseURL: 'http://localhost:5173' },
  webServer: [
    {
      command: 'pnpm --filter api run start:dev',
      url: 'http://localhost:3000/orders',
      // AuthGuard が x-user-id を要求するので GET /orders は 401 を返す。それでも
      // 起動待ちが成立するのは、Playwright の webServer の readiness 判定が
      // `statusCode >= 200 && statusCode < 404` を「起動した」とみなす仕様だから
      // である（playwright-core 1.62.0 の isURLAvailable。401 で通ることは §1.35 で
      // 実測済み）。到達確認としてはこれで十分なので URL はこのままにする。
      // ignoreHTTPSErrors はこの判定には効かない（rejectUnauthorized を落とすだけで、
      // http:// の URL には無意味）ため置かない。
      reuseExistingServer: true,
      timeout: 60_000,
    },
    {
      command: 'pnpm --filter web run dev',
      url: 'http://localhost:5173',
      reuseExistingServer: true,
      timeout: 60_000,
    },
  ],
});
