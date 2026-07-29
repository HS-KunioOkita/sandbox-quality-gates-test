import comments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

/**
 * 全パッケージ共通の ESLint ベース設定。
 *
 * 各パッケージの eslint.config.mjs は必ずこれを import して先頭に展開する。
 * ESLint 10 は対象ファイルから上方向に設定ファイルを探索し、見つかった設定で
 * 上位の設定を「置き換える」ため、ベースを継承するには各設定が自分で import する
 * 必要がある。
 */
export default tseslint.config(
  {
    // 生成物・依存はどのパッケージでも対象外
    ignores: ['**/dist/**', '**/coverage/**', '**/node_modules/**', '**/.turbo/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  comments.recommended,
  {
    linterOptions: {
      // 効いていない抑制コメント（＝負債）を検出する。
      // ESLint 10 の既定は warn なので、明示的に error へ上げる。
      reportUnusedDisableDirectives: 'error',
    },
    languageOptions: {
      parserOptions: { projectService: true },
    },
    rules: {
      // --- 手順書 §2.4 の厳選ルール ---
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unnecessary-condition': 'error',
      eqeqeq: ['error', 'always'],
      'no-console': 'error',

      // --- 抑制コメントを締める ---
      '@eslint-community/eslint-comments/no-unlimited-disable': 'error',
      '@eslint-community/eslint-comments/require-description': 'error',
    },
  },
  {
    // 設定ファイル自身は型情報付きルールの対象外にする。
    // tsconfig のプロジェクトに含まれない .js/.mjs に型情報付きルールを当てると
    // 「どのプロジェクトにも属さない」エラーになる。
    files: ['**/*.js', '**/*.mjs', '**/*.cjs'],
    extends: [tseslint.configs.disableTypeChecked],
  },
);
