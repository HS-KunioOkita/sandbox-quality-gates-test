import { useEffect, useState, type JSX } from 'react';
import { fetchOrders, type OrderView } from '../../api/client';
import { isDiscountApplied, sumDiscountedTotal } from './orderTotal';

interface OrderListProps {
  userId: string;
}

export function OrderList({ userId }: OrderListProps): JSX.Element {
  const [orders, setOrders] = useState<OrderView[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    setOrders(null);
    setError(null);

    fetchOrders(userId)
      .then((fetched) => {
        if (!cancelled) {
          setOrders(fetched);
        }
      })
      .catch((cause: unknown) => {
        if (!cancelled) {
          setError(cause instanceof Error ? cause.message : '不明なエラーが発生しました');
        }
      });

    return () => {
      cancelled = true;
    };
  }, [userId]);

  if (error !== null) {
    return <p role="alert">{error}</p>;
  }

  if (orders === null) {
    return <p>読み込み中...</p>;
  }

  if (orders.length === 0) {
    return <p>注文がありません</p>;
  }

  return (
    <section>
      <ul>
        {orders.map((order) => (
          <li key={order.id}>
            <span>{order.productName}</span>
            <span>
              {order.unitPrice} 円 × {order.quantity}
            </span>
            <span>{order.discountedTotal} 円</span>
            {isDiscountApplied(order) && (
              <span aria-label={`${order.productName} は割引適用`}>割引</span>
            )}
          </li>
        ))}
      </ul>
      <p>合計: {sumDiscountedTotal(orders)} 円</p>
    </section>
  );
}
