import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fetchOrders, type OrderView } from '../../api/client';
import { OrderList } from './OrderList';

// vi.mock はファイル先頭に巻き上げられるので、上の静的 import が
// そのままモックを受け取る。トップレベル await は不要。
vi.mock('../../api/client', () => ({ fetchOrders: vi.fn() }));

const fetchOrdersMock = vi.mocked(fetchOrders);

const SAMPLE_ORDERS: OrderView[] = [
  {
    id: 'order-1',
    productName: 'キーボード',
    unitPrice: 1200,
    quantity: 1,
    status: 'PAID',
    discountedTotal: 1080,
  },
  {
    id: 'order-2',
    productName: 'ケーブル',
    unitPrice: 300,
    quantity: 2,
    status: 'PENDING',
    discountedTotal: 600,
  },
];

describe('OrderList', () => {
  beforeEach(() => {
    fetchOrdersMock.mockReset();
  });

  it('読み込み中はその旨を表示する', () => {
    fetchOrdersMock.mockReturnValue(new Promise(() => undefined));

    render(<OrderList userId="user-1" />);

    expect(screen.getByText('読み込み中...')).toBeInTheDocument();
  });

  it('注文があるときは商品名と割引後合計を表示する', async () => {
    fetchOrdersMock.mockResolvedValue(SAMPLE_ORDERS);

    render(<OrderList userId="user-1" />);

    expect(await screen.findByText('キーボード')).toBeInTheDocument();
    expect(screen.getByText('ケーブル')).toBeInTheDocument();
    // 1080 + 600
    expect(screen.getByText('合計: 1680 円')).toBeInTheDocument();
  });

  it('割引が効いている注文には割引の印を付ける', async () => {
    fetchOrdersMock.mockResolvedValue(SAMPLE_ORDERS);

    render(<OrderList userId="user-1" />);

    // キーボードのみ割引が効いている
    expect(await screen.findByLabelText('キーボード は割引適用')).toBeInTheDocument();
    expect(screen.queryByLabelText('ケーブル は割引適用')).not.toBeInTheDocument();
  });

  it('注文が無いときはその旨を表示する', async () => {
    fetchOrdersMock.mockResolvedValue([]);

    render(<OrderList userId="user-1" />);

    expect(await screen.findByText('注文がありません')).toBeInTheDocument();
  });

  it('取得に失敗したときはエラーメッセージを表示する', async () => {
    fetchOrdersMock.mockRejectedValue(new Error('注文の取得に失敗しました（HTTP 401）'));

    render(<OrderList userId="user-1" />);

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '注文の取得に失敗しました（HTTP 401）',
    );
  });
});
