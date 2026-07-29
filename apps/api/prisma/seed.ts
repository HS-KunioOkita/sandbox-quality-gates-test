import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main(): Promise<void> {
  // 冪等にするため既存データを消してから投入する
  await prisma.order.deleteMany();
  await prisma.user.deleteMany();

  const member = await prisma.user.create({
    data: {
      email: 'member@example.com',
      name: '会員ユーザー',
      isMember: true,
      orders: {
        create: [
          // 1200 * 1 = 1200 → 閾値以上なので割引され 1080
          { productName: 'キーボード', unitPrice: 1200, quantity: 1, status: 'PAID' },
          // 300 * 2 = 600 → 閾値未満なので割引されず 600
          { productName: 'ケーブル', unitPrice: 300, quantity: 2, status: 'PENDING' },
        ],
      },
    },
  });

  const guest = await prisma.user.create({
    data: {
      email: 'guest@example.com',
      name: '非会員ユーザー',
      isMember: false,
      orders: {
        // 非会員なので 5000 でも割引されない
        create: [{ productName: 'モニター', unitPrice: 5000, quantity: 1, status: 'PAID' }],
      },
    },
  });

  console.info(`投入完了: member=${member.id} guest=${guest.id}`);
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => {
    void prisma.$disconnect();
  });
