import { Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { applyDiscount } from '../discount/discount';
import { PrismaService } from '../prisma/prisma.service';
import type { OrderResponseDto } from './dto/order-response.dto';

/** user を include して取得した Order */
type OrderWithUser = Prisma.OrderGetPayload<{ include: { user: true } }>;

/** 取得した注文をレスポンス形へ変換し、会員割引を適用した合計を載せる */
function toOrderResponse(order: OrderWithUser): OrderResponseDto {
  return {
    id: order.id,
    productName: order.productName,
    unitPrice: order.unitPrice,
    quantity: order.quantity,
    status: order.status,
    discountedTotal: applyDiscount(order.unitPrice * order.quantity, order.user.isMember),
  };
}

@Injectable()
export class OrdersService {
  constructor(private readonly prisma: PrismaService) {}

  /** 指定ユーザーの注文一覧を、会員割引を適用した合計付きで返す */
  async findByUser(userId: string): Promise<OrderResponseDto[]> {
    const orders = await this.prisma.order.findMany({
      where: { userId },
      include: { user: true },
      orderBy: { createdAt: 'desc' },
    });

    return orders.map(toOrderResponse);
  }
}
