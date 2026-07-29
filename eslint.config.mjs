import base from '@repo/eslint-config';

export default [
  ...base,
  {
    // 検証ハーネスとゲートスクリプトは bash / 単体 Node スクリプトで、
    // どの tsconfig プロジェクトにも属さない
    ignores: ['verification/lib/**', 'apps/**', 'docs/**'],
  },
];
