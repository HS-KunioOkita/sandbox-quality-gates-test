import fc from 'fast-check';
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

// 手順書 §4.5 の指定どおり環境変数で回数を切り替える。
// 毎 PR は 100（数秒）、nightly は FC_NUM_RUNS=10000 で深く探索する。
const NUM_RUNS = Number(process.env.FC_NUM_RUNS ?? 100);

describe('applyDiscount のプロパティ', () => {
  it('割引後の価格は元の価格を超えない', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 1_000_000 }),
        fc.boolean(),
        (price, isMember) => applyDiscount(price, isMember) <= price,
      ),
      { numRuns: NUM_RUNS },
    );
  });

  it('非会員の価格は常に元のまま', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 1_000_000 }),
        (price) => applyDiscount(price, false) === price,
      ),
      { numRuns: NUM_RUNS },
    );
  });

  it('割引後の価格は非負の整数', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 1_000_000 }),
        fc.boolean(),
        (price, isMember) => {
          const result = applyDiscount(price, isMember);
          return Number.isInteger(result) && result >= 0;
        },
      ),
      { numRuns: NUM_RUNS },
    );
  });
});
