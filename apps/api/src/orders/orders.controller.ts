import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiOkResponse } from '@nestjs/swagger';
import { AuthGuard, type AuthenticatedRequest } from '../auth/auth.guard';
import { CreateOrderDto } from './dto/create-order.dto';
import { OrderResponseDto } from './dto/order-response.dto';
import { OrdersService } from './orders.service';

@Controller('orders')
@UseGuards(AuthGuard)
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  /** 認証済みユーザー自身の注文一覧 */
  @Get()
  @ApiOkResponse({ type: [OrderResponseDto] })
  findAll(@Req() request: AuthenticatedRequest): Promise<OrderResponseDto[]> {
    return this.ordersService.findByUser(request.userId);
  }

  /** 認証済みユーザー自身の注文を作成 */
  @Post()
  @ApiOkResponse({ type: OrderResponseDto })
  create(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateOrderDto,
  ): Promise<OrderResponseDto> {
    return this.ordersService.create(request.userId, dto);
  }

  /** 認証済みユーザー自身の注文を 1 件取得 */
  @Get(':id')
  @ApiOkResponse({ type: OrderResponseDto })
  findOne(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ): Promise<OrderResponseDto> {
    return this.ordersService.findOneForUser(request.userId, id);
  }
}
