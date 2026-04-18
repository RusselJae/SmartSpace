import type { AdminRole } from '../auth/admin_role';

declare global {
  namespace Express {
    interface Request {
      /** Set by [requireAdminAuth] after a valid Bearer token. */
      adminAuth?: {
        readonly id: string;
        readonly email: string;
        readonly role: AdminRole;
      };
    }
  }
}

export {};
