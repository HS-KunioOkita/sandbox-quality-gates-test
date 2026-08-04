import { ApiProperty } from '@nestjs/swagger';
import { IsInt, IsString, MaxLength, Min, MinLength } from 'class-validator';

/** 注文作成の入力 */
export class CreateOrderDto {
  @ApiProperty({ minLength: 1, maxLength: 100 })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  productName!: string;

  @ApiProperty({ minimum: 0 })
  @IsInt()
  @Min(0)
  unitPrice!: number;

  @ApiProperty({ minimum: 1 })
  @IsInt()
  @Min(1)
  quantity!: number;
}
