import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { applyDiscount } from '../discount/discount';
import { PrismaService } from '../prisma/prisma.service';
import type { CreateOrderDto } from './dto/create-order.dto';
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

  /**
   * 注文を 1 件取得する。所有者でなければ拒否する。
   *
   * 見つからない場合と他人の注文である場合を区別して返す。実運用では
   * 存在の有無を漏らさないため両方 404 に倒す設計もありうるが、ここでは
   * 検証対象である手順書・設計書の記述（403 を返す経路を作る）に合わせる。
   */
  async findOneForUser(userId: string, orderId: string): Promise<OrderResponseDto> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { user: true },
    });

    if (order === null) {
      throw new NotFoundException('注文が見つかりません');
    }
    if (order.userId !== userId) {
      throw new ForbiddenException('この注文を参照する権限がありません');
    }

    return toOrderResponse(order);
  }

  /** 注文を作成し、会員割引を適用した合計付きで返す */
  async create(userId: string, dto: CreateOrderDto): Promise<OrderResponseDto> {
    try {
      const order = await this.prisma.order.create({
        data: {
          userId,
          productName: dto.productName,
          unitPrice: dto.unitPrice,
          quantity: dto.quantity,
        },
        include: { user: true },
      });

      return toOrderResponse(order);
    } catch (error) {
      // P2003 は外部キー制約違反。存在しないユーザー ID を渡された場合に起きる。
      // 未処理のままだと 500 になり、クライアントの誤りがサーバの障害として
      // 記録される（申し送り #12）。
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') {
        throw new BadRequestException('指定されたユーザーが存在しません');
      }
      throw error;
    }
  }
}
