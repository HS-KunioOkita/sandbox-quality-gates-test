import { IsInt, IsString, MaxLength, Min, MinLength } from 'class-validator';

/** 注文作成の入力 */
export class CreateOrderDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  productName!: string;

  @IsInt()
  @Min(0)
  unitPrice!: number;

  @IsInt()
  @Min(1)
  quantity!: number;
}
