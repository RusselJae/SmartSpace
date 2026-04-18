import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  listAdmins,
  createAdmin,
  updateAdmin,
  findAdminById,
  CreateAdminInput,
  UpdateAdminInput,
  resendAdminVerificationEmail,
  countAdmins,
} from '../services/admin_service';
import { assertStrongPassword, STRONG_PASSWORD_MESSAGE } from '../utils/password_policy';
import { listAdminActivityLogs } from '../services/admin_activity_log_service';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS, parseAdminRole, type AdminRole } from '../auth/admin_role';
import { config } from '../config/env';

export const adminRouter = Router();

/**
 * GET /api/admins
 * Lists all admins (super_admin only).
 */
adminRouter.get(
  '/',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.adminsManage),
  asyncHandler(async (_req, res) => {
    const admins = await listAdmins();
    res.json({ success: true, data: admins });
  }),
);

/**
 * POST /api/admins
 * Bootstrap: first admin (no JWT). After that: super_admin only.
 */
adminRouter.post(
  '/',
  asyncHandler(async (req, res, next) => {
    const n = await countAdmins();
    if (n === 0) {
      next();
      return;
    }
    requireAdminAuth(req, res, () =>
      requireAdminPermission(ADMIN_PERMISSIONS.adminsManage)(req, res, next),
    );
  }),
  asyncHandler(async (req, res) => {
    if (!config.adminJwt.secret.trim()) {
      return res.status(500).json({
        success: false,
        message: 'Server is not configured for admin login (ADMIN_JWT_SECRET).',
      });
    }

    const n = await countAdmins();
    let role: AdminRole = parseAdminRole(req.body.role) ?? 'operations_admin';
    if (n === 0) {
      role = 'super_admin';
    } else {
      const auth = req.adminAuth!;
      if (auth.role !== 'super_admin') {
        role = 'operations_admin';
      } else {
        const parsed = parseAdminRole(req.body.role);
        if (parsed != null) {
          role = parsed;
        }
      }
    }

    const input: CreateAdminInput = {
      email: req.body.email,
      password: req.body.password,
      fullName: req.body.fullName,
      role,
    };

    if (!input.email || !input.password || !input.fullName) {
      return res.status(400).json({
        success: false,
        message: 'Email, password, and full name are required',
      });
    }

    try {
      assertStrongPassword(input.password);
    } catch {
      return res.status(400).json({
        success: false,
        message: STRONG_PASSWORD_MESSAGE,
      });
    }

    try {
      const admin = await createAdmin(input);
      res.status(201).json({ success: true, data: admin });
    } catch (error) {
      if (error instanceof Error && error.message.includes('already exists')) {
        return res.status(409).json({
          success: false,
          message: error.message,
        });
      }
      throw error;
    }
  }),
);

/**
 * PATCH /api/admins/:id
 * fullName: self or super_admin. role: super_admin only.
 */
adminRouter.patch(
  '/:id',
  requireAdminAuth,
  asyncHandler(async (req, res) => {
    const auth = req.adminAuth!;
    const targetId = req.params.id;

    if (req.body.email !== undefined || req.body.password !== undefined) {
      return res.status(400).json({
        success: false,
        message: 'Email and password cannot be updated. Credentials are protected for security.',
      });
    }

    const input: { fullName?: string; role?: AdminRole } = {};

    if (req.body.fullName !== undefined) {
      if (auth.id !== targetId && auth.role !== 'super_admin') {
        return res.status(403).json({ success: false, message: 'Access denied' });
      }
      input.fullName = req.body.fullName;
    }

    if (req.body.role !== undefined) {
      if (auth.role !== 'super_admin') {
        return res.status(403).json({ success: false, message: 'Only a super admin can change roles' });
      }
      const r = parseAdminRole(req.body.role);
      if (r == null) {
        return res.status(400).json({ success: false, message: 'Invalid role' });
      }
      input.role = r;
    }

    if (input.fullName === undefined && input.role === undefined) {
      return res.status(400).json({ success: false, message: 'No valid fields to update' });
    }

    try {
      const admin = await updateAdmin(targetId, input as UpdateAdminInput);
      res.json({ success: true, data: admin });
    } catch (error) {
      if (error instanceof Error && error.message.includes('not found')) {
        return res.status(404).json({
          success: false,
          message: error.message,
        });
      }
      throw error;
    }
  }),
);

/**
 * GET /api/admins/activity-logs
 */
adminRouter.get(
  '/activity-logs',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.activityRead),
  asyncHandler(async (req, res) => {
    const limit = Number(req.query.limit ?? 50);
    let adminId = req.query.adminId != null ? String(req.query.adminId).trim() : '';
    const action = req.query.action != null ? String(req.query.action).trim() : '';
    const from = req.query.from != null ? new Date(String(req.query.from)) : null;
    const to = req.query.to != null ? new Date(String(req.query.to)) : null;

    if (req.adminAuth!.role !== 'super_admin') {
      adminId = req.adminAuth!.id;
    }

    const logs = await listAdminActivityLogs({
      limit,
      adminId: adminId.length > 0 ? adminId : undefined,
      action: action.length > 0 ? action : undefined,
      from: from != null && !Number.isNaN(from.getTime()) ? from : undefined,
      to: to != null && !Number.isNaN(to.getTime()) ? to : undefined,
    });
    res.json({ success: true, data: logs });
  }),
);

/**
 * POST /api/admins/:id/resend-verification
 */
adminRouter.post(
  '/:id/resend-verification',
  requireAdminAuth,
  asyncHandler(async (req, res) => {
    const auth = req.adminAuth!;
    if (auth.id !== req.params.id && auth.role !== 'super_admin') {
      return res.status(403).json({ success: false, message: 'Access denied' });
    }
    try {
      await resendAdminVerificationEmail(req.params.id);
      res.json({ success: true, message: 'Verification email sent' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to resend verification';
      res.status(400).json({ success: false, message });
    }
  }),
);

/**
 * GET /api/admins/:id
 */
adminRouter.get(
  '/:id',
  requireAdminAuth,
  asyncHandler(async (req, res) => {
    const auth = req.adminAuth!;
    if (auth.id !== req.params.id && auth.role !== 'super_admin') {
      return res.status(403).json({ success: false, message: 'Access denied' });
    }
    const admin = await findAdminById(req.params.id);
    if (admin == null) {
      return res.status(404).json({ success: false, message: 'Admin not found' });
    }
    res.json({ success: true, data: admin });
  }),
);
