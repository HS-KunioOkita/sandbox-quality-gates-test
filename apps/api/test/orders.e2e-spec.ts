import { ValidationPipe, type INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import type { OrderResponseDto } from '../src/orders/dto/order-response.dto';
import { PrismaService } from '../src/prisma/prisma.service';

describe('Orders (e2e)', () => {
  // app.getHttpServer() は INestApplication の TServer 型引数を省略すると
  // any になる（NestJS の既定）。ここを App で明示しないと、supertest への
  // 引数渡しと response.body へのアクセスが no-unsafe-* に引っかかる。
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let memberId: string;
  let otherId: string;
  let memberOrderId: string;
  let otherOrderId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    // main.ts の bootstrap と同じ ValidationPipe を張る。ここを揃えないと、
    // e2e は本番と違う入力検証の下で走ることになる。
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(async () => {
    await prisma.order.deleteMany();
    await prisma.user.deleteMany();

    const member = await prisma.user.create({
      data: { email: 'member@example.com', name: '会員', isMember: true },
    });
    const other = await prisma.user.create({
      data: { email: 'other@example.com', name: '他人', isMember: true },
    });
    memberId = member.id;
    otherId = other.id;

    const memberOrder = await prisma.order.create({
      data: { userId: memberId, productName: 'キーボード', unitPrice: 1200, quantity: 1 },
    });
    const otherOrder = await prisma.order.create({
      data: { userId: otherId, productName: 'マウス', unitPrice: 2000, quantity: 1 },
    });
    memberOrderId = memberOrder.id;
    otherOrderId = otherOrder.id;
  });

  it('自分の注文は 200 で取得できる', async () => {
    const response = await request(app.getHttpServer())
      .get(`/orders/${memberOrderId}`)
      .set('x-user-id', memberId);

    expect(response.status).toBe(200);
    // superagent の Response#body は any 固定なので、既知の型へ寄せてから読む。
    const body = response.body as OrderResponseDto;
    expect(body.productName).toBe('キーボード');
    expect(body.discountedTotal).toBe(1080);
  });

  it('他人の注文は 403 で拒否する', async () => {
    const response = await request(app.getHttpServer())
      .get(`/orders/${otherOrderId}`)
      .set('x-user-id', memberId);

    expect(response.status).toBe(403);
  });

  it('存在しない注文は 404 を返す', async () => {
    const response = await request(app.getHttpServer())
      .get('/orders/00000000-0000-0000-0000-000000000000')
      .set('x-user-id', memberId);

    expect(response.status).toBe(404);
  });

  it('存在しないユーザーの注文作成は 400 を返す', async () => {
    const response = await request(app.getHttpServer())
      .post('/orders')
      .set('x-user-id', '00000000-0000-0000-0000-000000000000')
      .send({ productName: 'ケーブル', unitPrice: 300, quantity: 2 });

    // 申し送り #12: 現状は Prisma の FK 違反（P2003）が未処理で 500 になる。
    expect(response.status).toBe(400);
  });
});
