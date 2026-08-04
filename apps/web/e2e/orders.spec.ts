import { expect, test } from '@playwright/test';

// seed.ts で固定した会員ユーザーの ID。
const MEMBER_ID = '11111111-1111-4111-8111-111111111111';

// 主要導線: ユーザー ID を入力すると、そのユーザーの注文一覧が
// 割引適用後の合計付きで表示される。
// 前提: pnpm db:up → db:migrate → db:seed が済んでいること。
test('注文一覧に割引適用後の合計が表示される', async ({ page }) => {
  await page.goto('/');

  await page.getByLabel('ユーザー ID').fill(MEMBER_ID);

  await expect(page.getByText('キーボード')).toBeVisible();
  // 1200 * 1 = 1200 は閾値以上なので 10% 引きで 1080
  await expect(page.getByText('1080 円')).toBeVisible();
});
