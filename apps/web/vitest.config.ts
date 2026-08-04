import react from '@vitejs/plugin-react';
import { configDefaults, defineConfig } from 'vitest/config';

// ../stryker.config.json の vitest.configFile がこのファイルを名指ししているため、
// Stryker の逸脱理由もここに書く。stryker.config.json は strict JSON（JSON.parse で
// 読まれる）でコメントを書けないため（実測。コメントを入れると
// "File contains invalid JSON" で落ちる）、隣接するこのファイルに書く。
//
// stryker.config.json に "plugins": ["@stryker-mutator/vitest-runner"] を明示している。
// 手順書 §5.2 は plugins を省略しているが、省略すると既定の自動検出
// (["@stryker-mutator/*"]) が使われ、@stryker-mutator/core 自身のインストール先から
// 相対的に fs.readdir する実装のため、pnpm の隔離 node_modules では
// @stryker-mutator/vitest-runner を発見できず、次のエラーで即クラッシュする（実測）:
//   Could not inject [class ChildProcessTestRunnerWorker]. Cause: Cannot find
//   TestRunner plugin "vitest". In fact, no TestRunner plugins were loaded.
//   Did you forget to install it?
// apps/api の stryker.config.json + jest-runner でも同型の不具合が再現している
// （task-1-report.md 参照）。plugins を明示すれば通常の Node モジュール解決に
// 回るため解消する（task-2-report.md 参照）。
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
