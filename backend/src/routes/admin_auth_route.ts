import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import { verifyAdminCredentials } from '../services/admin_service';

export const adminAuthRouter = Router();

/**
 * POST /api/admin-auth/login
 * Authenticates an admin with email and password.
 * 
 * Request body: { email: string, password: string }
 * Response: { success: true, data: Admin }
 * 
 * Returns 401 if credentials are invalid.
 */
adminAuthRouter.post(
  '/login',
  asyncHandler(async (req, res) => {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Email and password are required',
      });
    }

    const admin = await verifyAdminCredentials(email, password);

    if (admin == null) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password',
      });
    }

    res.json({ success: true, data: admin });
  }),
);




