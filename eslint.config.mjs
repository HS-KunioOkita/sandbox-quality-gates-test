import base from '@repo/eslint-config';

export default [
  ...base,
  {
    // docs は Markdown だけなので lint 対象外。
    // apps/** は絶対に入れないこと。files を伴わない ignores はグローバル ignore で
    // ディレクトリ走査そのものを止めるため、apps 配下が L1 ゲートの対象外になる。
    // apps/* は自分の eslint.config.mjs を持つが、それは「ルートで無視してよい」
    // という意味ではない。ルートの eslint . が全体を走査する。
    ignores: ['docs/**'],
  },
];
