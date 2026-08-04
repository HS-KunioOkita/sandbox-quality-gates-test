import { UnauthorizedException, type ExecutionContext } from '@nestjs/common';
import { AuthGuard, type AuthenticatedRequest } from './auth.guard';

/** switchToHttp().getRequest() が指定のリクエストを返す ExecutionContext を作る */
function contextWith(headers: Record<string, string | string[] | undefined>): ExecutionContext {
  const request = { headers } as unknown as AuthenticatedRequest;
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
}

describe('AuthGuard', () => {
  const guard = new AuthGuard();

  it('x-user-id があれば通し、request に userId を載せる', () => {
    const context = contextWith({ 'x-user-id': 'user-1' });

    expect(guard.canActivate(context)).toBe(true);
    expect(context.switchToHttp().getRequest<AuthenticatedRequest>().userId).toBe('user-1');
  });

  it('x-user-id が無ければ UnauthorizedException を投げる', () => {
    expect(() => guard.canActivate(contextWith({}))).toThrow(UnauthorizedException);
  });

  it('x-user-id が空文字なら UnauthorizedException を投げる', () => {
    expect(() => guard.canActivate(contextWith({ 'x-user-id': '' }))).toThrow(
      UnauthorizedException,
    );
  });

  it('x-user-id が配列（ヘッダ重複）なら UnauthorizedException を投げる', () => {
    // express はヘッダが重複すると配列を返す。typeof !== 'string' の分岐を通る。
    expect(() => guard.canActivate(contextWith({ 'x-user-id': ['a', 'b'] }))).toThrow(
      UnauthorizedException,
    );
  });
});
