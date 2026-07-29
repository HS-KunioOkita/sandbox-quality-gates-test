import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard, type AuthenticatedRequest } from '../auth/auth.guard';
import { CreateOrderDto } from './dto/create-order.dto';
import type { OrderResponseDto } from './dto/order-response.dto';
import { OrdersService } from './orders.service';

@Controller('orders')
@UseGuards(AuthGuard)
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  /** 認証済みユーザー自身の注文一覧 */
  @Get()
  findAll(@Req() request: AuthenticatedRequest): Promise<OrderResponseDto[]> {
    return this.ordersService.findByUser(request.userId);
  }

  /** 認証済みユーザー自身の注文を作成 */
  @Post()
  create(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateOrderDto,
  ): Promise<OrderResponseDto> {
    return this.ordersService.create(request.userId, dto);
  }
}
