import type { OrderView } from '../../api/client';

/** 全注文の割引後合計 */
export function sumDiscountedTotal(orders: readonly OrderView[]): number {
  return orders.reduce((sum, order) => sum + order.discountedTotal, 0);
}

/** この注文に割引が効いているか */
export function isDiscountApplied(order: OrderView): boolean {
  return order.discountedTotal < order.unitPrice * order.quantity;
}
