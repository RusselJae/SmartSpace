import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  verifyAdminCredentials,
  verifyAdminEmail,
  verifyAdminEmailByCode,
  requestAdminPasswordReset,
  resetAdminPasswordWithToken,
  FORGOT_PASSWORD_ACK,
} from '../services/admin_service';
import { buildAdminVerifyEmailLandingHtml } from './admin_auth_verify_html';
import { signAdminAccessToken } from '../auth/admin_jwt';
import { config } from '../config/env';

export const adminAuthRouter = Router();

/**
 * GET /api/admin-auth/verify-email?token=...&ui=1
 * Must be registered before routes that could capture `verify-email` as a param.
 */
adminAuthRouter.get(
  '/verify-email',
  asyncHandler(async (req, res) => {
    const token = (req.query.token as string | undefined) ?? '';
    const emailLanding = req.query.ui === '1' || req.query.source === 'email';

    if (!token.trim()) {
      if (emailLanding) {
        return res
          .status(400)
          .type('html')
          .send(
            buildAdminVerifyEmailLandingHtml(
              false,
              'This verification link is missing a token. Request a new email from your administrator.',
            ),
          );
      }
      return res.status(400).json({
        success: false,
        message: 'Verification token is required',
      });
    }

    try {
      const admin = await verifyAdminEmail(token);
      if (emailLanding) {
        return res
          .status(200)
          .type('html')
          .send(
            buildAdminVerifyEmailLandingHtml(
              true,
              'Your admin email is verified. You can sign in to the admin console.',
            ),
          );
      }
      res.json({
        success: true,
        message: 'Email verified successfully',
        data: admin,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to verify email';
      if (emailLanding) {
        return res.status(400).type('html').send(buildAdminVerifyEmailLandingHtml(false, message));
      }
      res.status(400).json({
        success: false,
        message,
      });
    }
  }),
);

/**
 * POST /api/admin-auth/login
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

    try {
      const admin = await verifyAdminCredentials(email, password);

      if (admin == null) {
        return res.status(401).json({
          success: false,
          message: 'Invalid email or password',
        });
      }

      if (!config.adminJwt.secret.trim()) {
        return res.status(500).json({
          success: false,
          message: 'Server is not configured for admin sessions (ADMIN_JWT_SECRET).',
        });
      }

      const token = signAdminAccessToken({
        sub: admin.id,
        email: admin.email,
        role: admin.role,
      });

      res.json({ success: true, data: admin, token });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Sign-in failed';
      if (message.toLowerCase().includes('verify your email')) {
        return res.status(403).json({ success: false, message });
      }
      throw error;
    }
  }),
);

/**
 * POST /api/admin-auth/verify-email-code
 */
adminAuthRouter.post(
  '/verify-email-code',
  asyncHandler(async (req, res) => {
    const code = (req.body.code as string | undefined) ?? '';
    if (!code.trim()) {
      return res.status(400).json({ success: false, message: 'Verification code is required' });
    }
    try {
      const admin = await verifyAdminEmailByCode(code.trim());
      res.json({ success: true, message: 'Email verified successfully', data: admin });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Invalid verification code';
      res.status(400).json({ success: false, message });
    }
  }),
);

/**
 * POST /api/admin-auth/forgot-password
 */
adminAuthRouter.post(
  '/forgot-password',
  asyncHandler(async (req, res) => {
    const email = (req.body.email as string | undefined) ?? '';
    await requestAdminPasswordReset(email);
    res.json({ success: true, message: FORGOT_PASSWORD_ACK });
  }),
);

/**
 * POST /api/admin-auth/reset-password
 */
adminAuthRouter.post(
  '/reset-password',
  asyncHandler(async (req, res) => {
    const token = (req.body.token as string | undefined) ?? '';
    const newPassword = (req.body.newPassword as string | undefined) ?? '';
    try {
      await resetAdminPasswordWithToken(token, newPassword);
      res.json({ success: true, message: 'Password updated. You can sign in now.' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to reset password';
      res.status(400).json({ success: false, message });
    }
  }),
);
