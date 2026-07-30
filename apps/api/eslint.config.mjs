import base from '@repo/eslint-config';

export default [
  ...base,
  {
    ignores: ['dist/**', 'coverage/**', 'reports/**'],
  },
  {
    // Prisma のシードスクリプトは CLI から手で叩く運用スクリプトであり、
    // 実行結果を標準出力に出すことが目的なので no-console を無効にする。
    // アプリ本体（src/**）には適用しない。
    files: ['prisma/**/*.ts'],
    rules: { 'no-console': 'off' },
  },
];
