import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  listAdmins,
  createAdmin,
  updateAdmin,
  findAdminById,
  CreateAdminInput,
  UpdateAdminInput,
} from '../services/admin_service';
import { listAdminActivityLogs } from '../services/admin_activity_log_service';

export const adminRouter = Router();

/**
 * GET /api/admins
 * Lists all admins in the system.
 * 
 * Response: { success: true, data: Admin[] }
 * Note: Password hashes are never included in responses.
 */
adminRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const admins = await listAdmins();
    res.json({ success: true, data: admins });
  }),
);

/**
 * POST /api/admins
 * Creates a new admin account.
 * 
 * Request body: { email: string, password: string, fullName: string }
 * Response: { success: true, data: Admin }
 * 
 * The password is hashed before storage. Email must be unique.
 */
adminRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const input: CreateAdminInput = {
      email: req.body.email,
      password: req.body.password,
      fullName: req.body.fullName,
    };

    // Validate required fields
    if (!input.email || !input.password || !input.fullName) {
      return res.status(400).json({
        success: false,
        message: 'Email, password, and full name are required',
      });
    }

    // Validate password strength (minimum 6 characters)
    if (input.password.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters long',
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
 * Updates an admin's information.
 * 
 * Request body: { fullName?: string }
 * Response: { success: true, data: Admin }
 * 
 * SECURITY: Email and password CANNOT be updated through this endpoint.
 * This is intentional to prevent credential changes that could compromise security.
 */
adminRouter.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    const input: UpdateAdminInput = {
      fullName: req.body.fullName,
    };

    // Explicitly reject any attempts to update credentials
    if (req.body.email !== undefined || req.body.password !== undefined) {
      return res.status(400).json({
        success: false,
        message: 'Email and password cannot be updated. Credentials are protected for security.',
      });
    }

    try {
      const admin = await updateAdmin(req.params.id, input);
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
 * GET /api/admins/activity-logs?limit=50
 * Returns recent critical admin activity entries for accountability.
 */
adminRouter.get(
  '/activity-logs',
  asyncHandler(async (req, res) => {
    const limit = Number(req.query.limit ?? 50);
    const adminId = req.query.adminId != null ? String(req.query.adminId).trim() : '';
    const action = req.query.action != null ? String(req.query.action).trim() : '';
    const from = req.query.from != null ? new Date(String(req.query.from)) : null;
    const to = req.query.to != null ? new Date(String(req.query.to)) : null;
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
 * GET /api/admins/:id
 * Gets a specific admin by ID.
 * 
 * Response: { success: true, data: Admin }
 * Returns 404 if admin not found.
 *
 * IMPORTANT: This route must be registered AFTER more specific routes
 * like `/activity-logs`, otherwise `/activity-logs` is treated as an id.
 */
adminRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const admin = await findAdminById(req.params.id);
    if (admin == null) {
      return res.status(404).json({ success: false, message: 'Admin not found' });
    }
    res.json({ success: true, data: admin });
  }),
);































