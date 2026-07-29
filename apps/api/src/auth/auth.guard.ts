import {
  type CanActivate,
  type ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';

/** AuthGuard が userId を載せたあとのリクエスト */
export interface AuthenticatedRequest extends Request {
  userId: string;
}

@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const userId = request.headers['x-user-id'];

    if (typeof userId !== 'string' || userId.length === 0) {
      throw new UnauthorizedException('x-user-id ヘッダが必要です');
    }

    request.userId = userId;
    return true;
  }
}
