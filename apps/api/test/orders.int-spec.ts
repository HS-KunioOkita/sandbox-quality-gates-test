import { OrdersService } from '../src/orders/orders.service';
import { PrismaService } from '../src/prisma/prisma.service';

describe('OrdersService（実 DB）', () => {
  let prisma: PrismaService;
  let service: OrdersService;

  beforeAll(async () => {
    // setup-db.ts の beforeAll が先に走り、DATABASE_URL がコンテナのものに
    // 差し替わっている。PrismaClient は new した時点の URL を掴むので、
    // ここより前にインスタンス化してはいけない。
    prisma = new PrismaService();
    await prisma.$connect();
    service = new OrdersService(prisma);
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await prisma.order.deleteMany();
    await prisma.user.deleteMany();
  });

  it('自分の注文だけを、会員割引を適用した合計付きで返す', async () => {
    const member = await prisma.user.create({
      data: { email: 'member@example.com', name: '会員', isMember: true },
    });
    const other = await prisma.user.create({
      data: { email: 'other@example.com', name: '他人', isMember: true },
    });
    await prisma.order.create({
      data: { userId: member.id, productName: 'キーボード', unitPrice: 1200, quantity: 1 },
    });
    await prisma.order.create({
      data: { userId: other.id, productName: 'マウス', unitPrice: 2000, quantity: 1 },
    });

    const orders = await service.findByUser(member.id);

    expect(orders).toHaveLength(1);
    expect(orders[0]?.productName).toBe('キーボード');
    // 1200 * 1 = 1200 は閾値 1000 以上なので 10% 引きで 1080
    expect(orders[0]?.discountedTotal).toBe(1080);
  });

  it('非会員には割引を適用しない', async () => {
    const guest = await prisma.user.create({
      data: { email: 'guest@example.com', name: '非会員', isMember: false },
    });
    await prisma.order.create({
      data: { userId: guest.id, productName: 'モニター', unitPrice: 5000, quantity: 1 },
    });

    const orders = await service.findByUser(guest.id);

    expect(orders[0]?.discountedTotal).toBe(5000);
  });
});
