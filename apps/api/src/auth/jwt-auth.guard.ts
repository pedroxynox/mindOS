import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';

export interface AuthenticatedUser {
  id: string;
}

interface RequestWithUser extends Request {
  user?: AuthenticatedUser;
}

/**
 * Guard that validates the Bearer access token and attaches the user to the
 * request. Applied to protected routes (e.g. capture, from F1b).
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithUser>();
    const token = this.extractToken(request);
    if (!token) {
      throw new UnauthorizedException('Falta el token de acceso.');
    }

    try {
      const payload = await this.jwt.verifyAsync<{
        sub: string;
        type: string;
      }>(token);
      if (payload.type !== 'access') {
        throw new UnauthorizedException('Tipo de token incorrecto.');
      }
      request.user = { id: payload.sub };
      return true;
    } catch {
      throw new UnauthorizedException('Token inválido o expirado.');
    }
  }

  private extractToken(request: RequestWithUser): string | undefined {
    const header = request.headers.authorization;
    if (!header) {
      return undefined;
    }
    const [scheme, value] = header.split(' ');
    return scheme === 'Bearer' ? value : undefined;
  }
}
