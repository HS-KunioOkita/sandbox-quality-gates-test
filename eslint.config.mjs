import base from '@repo/eslint-config';

export default [
  ...base,
  {
    // 検証ハーネスは単体 Node スクリプトで、どの tsconfig プロジェクトにも属さない。
    // apps/** は入れないこと。files を伴わない ignores はグローバル ignore で
    // ディレクトリ走査そのものを止めるため、apps 配下がゲートの対象外になる。
    ignores: ['verification/lib/**', 'docs/**'],
  },
];
