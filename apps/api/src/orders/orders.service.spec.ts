import { Test } from '@nestjs/testing';
import { PrismaService } from '../prisma/prisma.service';
import { OrdersService } from './orders.service';

interface MockPrisma {
  order: {
    findMany: jest.Mock;
  };
}

function createMockPrisma(): MockPrisma {
  return { order: { findMany: jest.fn() } };
}

describe('OrdersService', () => {
  let service: OrdersService;
  let prisma: MockPrisma;

  beforeEach(async () => {
    prisma = createMockPrisma();
    const moduleRef = await Test.createTestingModule({
      providers: [OrdersService, { provide: PrismaService, useValue: prisma }],
    }).compile();
    service = moduleRef.get(OrdersService);
  });

  describe('findByUser', () => {
    it('会員の注文には割引を適用した合計を返す', async () => {
      prisma.order.findMany.mockResolvedValue([
        {
          id: 'order-1',
          productName: 'キーボード',
          unitPrice: 1200,
          quantity: 1,
          status: 'PAID',
          user: { isMember: true },
        },
      ]);

      const result = await service.findByUser('user-1');

      // 1200 * 1 = 1200 → 会員かつ閾値以上なので 1080
      expect(result).toEqual([
        {
          id: 'order-1',
          productName: 'キーボード',
          unitPrice: 1200,
          quantity: 1,
          status: 'PAID',
          discountedTotal: 1080,
        },
      ]);
    });

    it('非会員の注文には割引を適用しない', async () => {
      prisma.order.findMany.mockResolvedValue([
        {
          id: 'order-2',
          productName: 'モニター',
          unitPrice: 5000,
          quantity: 1,
          status: 'PAID',
          user: { isMember: false },
        },
      ]);

      const result = await service.findByUser('user-2');

      expect(result[0]?.discountedTotal).toBe(5000);
    });

    it('単価×数量の合計に対して割引を判定する', async () => {
      prisma.order.findMany.mockResolvedValue([
        {
          id: 'order-3',
          productName: 'ケーブル',
          unitPrice: 300,
          quantity: 2,
          status: 'PENDING',
          user: { isMember: true },
        },
      ]);

      const result = await service.findByUser('user-1');

      // 300 * 2 = 600 → 閾値 1000 未満なので割引されない
      expect(result[0]?.discountedTotal).toBe(600);
    });

    it('指定ユーザーで絞り込み、user を同時に取得する（N+1 を避ける）', async () => {
      prisma.order.findMany.mockResolvedValue([]);

      await service.findByUser('user-1');

      expect(prisma.order.findMany).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        include: { user: true },
        orderBy: { createdAt: 'desc' },
      });
    });

    it('注文が無いときは空配列を返す', async () => {
      prisma.order.findMany.mockResolvedValue([]);

      await expect(service.findByUser('user-1')).resolves.toEqual([]);
    });
  });
});
