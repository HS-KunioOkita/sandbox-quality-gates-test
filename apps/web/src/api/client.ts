import type { OrderStatus } from '@repo/shared';

/** 注文一覧の表示に使う 1 件分のデータ */
export interface OrderView {
  id: string;
  productName: string;
  unitPrice: number;
  quantity: number;
  status: OrderStatus;
  discountedTotal: number;
}

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

/** 指定ユーザーの注文一覧を取得する */
export async function fetchOrders(userId: string): Promise<OrderView[]> {
  const response = await fetch(`${API_BASE_URL}/orders`, {
    headers: { 'x-user-id': userId },
  });

  if (!response.ok) {
    throw new Error(`注文の取得に失敗しました（HTTP ${response.status}）`);
  }

  return (await response.json()) as OrderView[];
}
