import type { OrderStatus } from '@repo/shared';

/** 注文一覧・注文作成のレスポンス */
export interface OrderResponseDto {
  id: string;
  productName: string;
  unitPrice: number;
  quantity: number;
  status: OrderStatus;
  /** 会員割引を適用した合計金額 */
  discountedTotal: number;
}
