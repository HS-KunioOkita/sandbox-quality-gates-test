import { MEMBER_DISCOUNT_MIN_PRICE } from '@repo/shared';
import { applyDiscount } from './discount';

describe('applyDiscount', () => {
  it('非会員は割引されない', () => {
    expect(applyDiscount(2000, false)).toBe(2000);
  });

  it('会員で閾値ちょうどのときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE, true)).toBe(900);
  });

  it('会員で閾値のすぐ下のときは割引されない', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE - 1, true)).toBe(999);
  });

  it('会員で閾値のすぐ上のときは割引される', () => {
    expect(applyDiscount(MEMBER_DISCOUNT_MIN_PRICE + 1, true)).toBe(900);
  });

  it('割引後の端数は切り捨てる', () => {
    // 1005 * 0.9 = 904.5 → 904
    expect(applyDiscount(1005, true)).toBe(904);
  });

  it('0 円は割引されない', () => {
    expect(applyDiscount(0, true)).toBe(0);
  });
});
