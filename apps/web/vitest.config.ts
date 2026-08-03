import react from '@vitejs/plugin-react';
import { configDefaults, defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    coverage: { provider: 'v8', reporter: ['text', 'lcov'] },
    // e2e/ は Playwright 専用ディレクトリ。vitest の既定 include は
    // '**/*.spec.ts' にもマッチするため、除外しないと vitest が
    // e2e/orders.spec.ts を自分のテストとして拾おうとして落ちる
    // （Playwright の test() は vitest から直接呼べない）。
    exclude: [...configDefaults.exclude, 'e2e/**'],
  },
});
