import { MEMBER_DISCOUNT_MIN_PRICE, MEMBER_DISCOUNT_RATE } from '@repo/shared';

/**
 * 会員割引を適用した価格を返す。
 *
 * 会員であり、かつ price が MEMBER_DISCOUNT_MIN_PRICE 以上のときだけ割引する。
 * 割引後の端数は切り捨てる。
 */
export function applyDiscount(price: number, isMember: boolean): number {
  if (!isMember) {
    return price;
  }
  if (price < MEMBER_DISCOUNT_MIN_PRICE) {
    return price;
  }
  return Math.floor(price * (1 - MEMBER_DISCOUNT_RATE));
}
