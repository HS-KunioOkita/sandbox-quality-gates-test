import { cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import { afterEach } from 'vitest';

// Vitest は globals: false のため RTL の自動 cleanup が働かない。
// 明示的に登録しないとテスト間で DOM が蓄積し、前のテストが残したノードに
// 対してアサーションが通ってしまう。
afterEach(() => {
  cleanup();
});
