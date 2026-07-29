import { describe, expect, it } from 'vitest';
import type { OrderView } from '../../api/client';
import { isDiscountApplied, sumDiscountedTotal } from './orderTotal';

function makeOrder(overrides: Partial<OrderView> = {}): OrderView {
  return {
    id: 'order-1',
    productName: 'キーボード',
    unitPrice: 1200,
    quantity: 1,
    status: 'PAID',
    discountedTotal: 1080,
    ...overrides,
  };
}

describe('sumDiscountedTotal', () => {
  it('空配列のときは 0 を返す', () => {
    expect(sumDiscountedTotal([])).toBe(0);
  });

  it('全注文の割引後合計を足し上げる', () => {
    const orders = [makeOrder({ discountedTotal: 1080 }), makeOrder({ discountedTotal: 600 })];
    expect(sumDiscountedTotal(orders)).toBe(1680);
  });
});

describe('isDiscountApplied', () => {
  it('割引後の合計が単価×数量より小さいときは true', () => {
    expect(isDiscountApplied(makeOrder({ unitPrice: 1200, quantity: 1, discountedTotal: 1080 }))).toBe(
      true,
    );
  });

  it('割引後の合計が単価×数量と等しいときは false', () => {
    expect(isDiscountApplied(makeOrder({ unitPrice: 300, quantity: 2, discountedTotal: 600 }))).toBe(
      false,
    );
  });
});
