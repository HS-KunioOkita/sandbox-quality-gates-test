import { ApiProperty } from '@nestjs/swagger';
import type { OrderStatus } from '@repo/shared';

/**
 * 注文一覧・注文作成のレスポンス
 *
 * class にしているのは @nestjs/swagger が実行時のデコレータメタデータから
 * スキーマを組み立てるためである。interface は型消去で実行時に残らないので
 * OpenAPI に 1 つも項目が出ない。手順書 §4.4 はこの前提に触れていない。
 */
export class OrderResponseDto {
  @ApiProperty()
  id!: string;

  @ApiProperty()
  productName!: string;

  @ApiProperty()
  unitPrice!: number;

  @ApiProperty()
  quantity!: number;

  @ApiProperty({ enum: ['PENDING', 'PAID', 'CANCELLED'] })
  status!: OrderStatus;

  /** 会員割引を適用した合計金額 */
  @ApiProperty()
  discountedTotal!: number;
}
