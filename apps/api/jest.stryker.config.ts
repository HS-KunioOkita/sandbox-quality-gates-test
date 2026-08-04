/**
 * @jest-config-loader ts-node
 *
 * Node 24 のネイティブ TypeScript サポート（strip-types）により、Jest 30 の
 * jest-config は既定でこの設定ファイル自体を native import で読もうとする。
 * その経路は拡張子なしの相対 import（`./jest.config`）を解決できず
 * ERR_MODULE_NOT_FOUND で落ちる（実測。tsc の型チェックは通るのに Jest の
 * 起動だけが失敗する）。docblock で ts-node ローダーを明示すると、
 * tsconfig の moduleResolution（node10）どおりに解決する ts-node 経由の
 * require に切り替わり解消する。ブリーフのコードそのものは変えず、
 * ローダー指定の docblock だけを追加した（task-1-report.md 参照）。
 *
 * なお `../stryker.config.json` に `"plugins": ["@stryker-mutator/jest-runner"]`
 * を明示しているのも同種の逸脱だが、stryker.config.json は strict JSON で
 * コメントを書けないため理由をここに書く。既定の `plugins: ["@stryker-mutator/*"]`
 * は @stryker-mutator/core 自身のインストール先から相対的にディレクトリを
 * 列挙する実装で、pnpm の隔離 node_modules では jest-runner を発見できず
 * 起動時に "Cannot find TestRunner plugin \"jest\"" で落ちる（task-1-report.md 参照）。
 */
import type { Config } from 'jest';
import { unitProject } from './jest.config';

// Stryker が使う Jest 設定。unit プロジェクトだけを持つ。
//
// jest.config.ts をそのまま渡すと integration / e2e が含まれ、
// test/setup-db.ts の Testcontainers が **mutant の数だけ** PostgreSQL コンテナを
// 起動する（申し送り #28）。手順書 §5.2 は `jest: { configFile: 'jest.config.ts' }`
// と書いており、この相互作用に触れていない。逸脱の理由は
// docs/superpowers/phase0-findings.md に記録する。
const config: Config = {
  ...unitProject,
  rootDir: '.',
};

export default config;
