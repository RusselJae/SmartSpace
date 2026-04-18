import jwt from 'jsonwebtoken';
import { config } from '../config/env';
import type { AdminRole } from './admin_role';

export type AdminAccessTokenPayload = {
  readonly sub: string;
  readonly email: string;
  readonly role: AdminRole;
};

export const signAdminAccessToken = (payload: AdminAccessTokenPayload): string => {
  const options: jwt.SignOptions = {
    expiresIn: config.adminJwt.expiresIn as jwt.SignOptions['expiresIn'],
  };
  return jwt.sign({ sub: payload.sub, email: payload.email, role: payload.role }, config.adminJwt.secret, options);
};

export const verifyAdminAccessToken = (token: string): AdminAccessTokenPayload => {
  const decoded = jwt.verify(token, config.adminJwt.secret) as jwt.JwtPayload & {
    sub?: string;
    email?: string;
    role?: AdminRole;
  };
  if (!decoded.sub || !decoded.email || !decoded.role) {
    throw new Error('Invalid token payload');
  }
  return {
    sub: decoded.sub,
    email: decoded.email,
    role: decoded.role,
  };
};
