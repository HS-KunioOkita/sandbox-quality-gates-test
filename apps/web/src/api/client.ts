import type { paths } from './schema';

/**
 * 注文一覧の表示に使う 1 件分のデータ
 *
 * 生成された OpenAPI の型から導出する。手で書いた interface に戻すと、
 * API 側の DTO が変わっても Web 側が気づかない状態に戻る（申し送り #10）。
 */
export type OrderView =
  paths['/orders']['get']['responses'][200]['content']['application/json'][number];

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
