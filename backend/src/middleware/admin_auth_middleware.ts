import type { RequestHandler } from 'express';
import { verifyAdminAccessToken } from '../auth/admin_jwt';
import type { AdminRole } from '../auth/admin_role';
import { adminHasPermission } from '../auth/admin_role';
import { findAdminById } from '../services/admin_service';

/**
 * Reads Bearer token, verifies JWT + DB admin row, attaches [req.adminAuth].
 */
export const requireAdminAuth: RequestHandler = async (req, res, next) => {
  try {
    const header = req.headers.authorization;
    const raw = header?.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (!raw) {
      return res.status(401).json({ success: false, message: 'Admin authentication required' });
    }
    const payload = verifyAdminAccessToken(raw);
    const admin = await findAdminById(payload.sub);
    if (admin == null || !admin.emailVerified) {
      return res.status(401).json({ success: false, message: 'Invalid admin session' });
    }
    if (admin.role !== payload.role) {
      return res.status(401).json({ success: false, message: 'Session outdated; sign in again' });
    }
    req.adminAuth = {
      id: admin.id,
      email: admin.email,
      role: admin.role as AdminRole,
    };
    next();
  } catch {
    return res.status(401).json({ success: false, message: 'Invalid or expired admin token' });
  }
};

export const requireAdminPermission = (permission: string): RequestHandler => {
  return (req, res, next) => {
    const auth = req.adminAuth;
    if (auth == null) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }
    if (!adminHasPermission(auth.role, permission)) {
      return res.status(403).json({ success: false, message: 'You do not have permission for this action' });
    }
    next();
  };
};

/**
 * Listing all made-to-order requests is admin-only; per-user listing stays public for the storefront.
 */
export const requireAdminForGlobalMadeToOrderList: RequestHandler = (req, res, next) => {
  const userId = typeof req.query.userId === 'string' ? req.query.userId.trim() : '';
  if (userId.length > 0) {
    next();
    return;
  }
  requireAdminAuth(req, res, () => requireAdminPermission('orders:read')(req, res, next));
};
