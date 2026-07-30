import base from '@repo/eslint-config';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  ...base,
  {
    ignores: ['dist/**', 'coverage/**', 'reports/**', '.playwright-mcp/**'],
  },
  reactHooks.configs.flat['recommended-latest'],
  jsxA11y.flatConfigs.recommended,
  {
    rules: {
      // warn ではなく error にする
      'react-hooks/exhaustive-deps': 'error',
      // Web から API の内部実装を直接 import させない
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            { group: ['**/apps/api/src/**'], message: '共有は packages/shared 経由で' },
          ],
        },
      ],
    },
  },
];
