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
      // AuthGuard が x-user-id を要求するので 401 が返る。到達確認としては
      // これで十分なので、2xx 以外も「起動した」とみなす。
      ignoreHTTPSErrors: true,
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
