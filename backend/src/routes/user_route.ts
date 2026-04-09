import path from 'path';

import multer from 'multer';
import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import { 
  listUsers, 
  createUser, 
  updateUser, 
  findUserById, 
  verifyUserEmail,
  verifyUserEmailByCode,
  resendVerificationToken,
  CreateUserInput,
  verifyUserCredentials,
  changeUserPassword,
} from '../services/user_service';
import { EmailService } from '../services/email_service';
import { avatarsDir, ensureUploadsDirectories } from '../utils/uploads';
import { generateId } from '../utils/id_generator';
import { config } from '../config/env';
import { isCloudinaryUploadsEnabled, uploadImageBuffer } from '../services/cloudinary_service';
import { isSupabaseStorageEnabled, uploadToSupabaseStorage } from '../services/supabase_storage_service';
import { shouldUseMemoryBufferUpload } from '../services/storage_mode';

/** Escape text embedded in minimal HTML landing pages (verification errors, etc.). */
function escapeHtmlVerificationPage(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Safe http(s) href for "continue to app" on the post-verify landing page. */
function safeStorefrontHref(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return '';
  try {
    const u = new URL(trimmed);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return '';
    return u.toString();
  } catch {
    return '';
  }
}

/**
 * Browser-friendly page after the user taps "Verify" in email (Gmail/Outlook allow https links;
 * custom schemes like smartspace:// are often inert in webmail).
 */
function buildVerifyEmailLandingHtml(ok: boolean, message: string): string {
  const safeMessage = escapeHtmlVerificationPage(message);
  const continueHref = safeStorefrontHref(config.frontend.url);
  const continueBlock = continueHref
    ? `<p style="margin:28px 0 0;"><a href="${escapeHtmlVerificationPage(continueHref)}" style="display:inline-block;padding:14px 28px;background:#5D4037;color:#fff;text-decoration:none;border-radius:12px;font-weight:600;font-family:system-ui,sans-serif;">Continue to Wood Home</a></p>`
    : '';
  const title = ok ? 'Email verified' : 'Verification issue';
  const accent = ok ? '#2E7D32' : '#C62828';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtmlVerificationPage(title)}</title>
</head>
<body style="margin:0;font-family:system-ui,-apple-system,sans-serif;background:#f5f0eb;color:#3e2723;">
  <div style="max-width:520px;margin:48px auto;padding:32px 28px;background:#fff;border-radius:16px;box-shadow:0 8px 32px rgba(0,0,0,.08);text-align:center;">
    <h1 style="margin:0 0 12px;font-size:22px;color:${accent};">${escapeHtmlVerificationPage(title)}</h1>
    <p style="margin:0;font-size:16px;line-height:1.55;color:#5d4037;">${safeMessage}</p>
    ${continueBlock}
    <p style="margin:32px 0 0;font-size:13px;color:#a1887f;">Wood Home Furniture Trading</p>
  </div>
</body>
</html>`;
}

export const userRouter = Router();

ensureUploadsDirectories();

const avatarDiskStorage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    cb(null, avatarsDir);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${generateId('avatar')}${ext}`);
  },
});

const avatarUpload = multer({
  storage: shouldUseMemoryBufferUpload() ? multer.memoryStorage() : avatarDiskStorage,
  limits: { fileSize: 6 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    // Check mimetype first
    if (file.mimetype && file.mimetype.startsWith('image/')) {
      return cb(null, true);
    }
    // Fallback: check file extension if mimetype is missing
    const ext = path.extname(file.originalname).toLowerCase();
    const imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    if (imageExts.includes(ext)) {
      return cb(null, true);
    }
    cb(new Error('Only image files are allowed'));
  },
});

userRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const users = await listUsers();
    res.json({ success: true, data: users });
  }),
);

userRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const user = await findUserById(req.params.id);
    if (user == null) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    res.json({ success: true, data: user });
  }),
);

userRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const input: CreateUserInput = {
      email: req.body.email,
      fullName: req.body.fullName,
      password: req.body.password,
      username: req.body.username,
      phoneNumber: req.body.phoneNumber,
      gender: req.body.gender,
    };
    if (!input.email || !input.fullName || !input.password) {
      return res.status(400).json({ success: false, message: 'Email, full name, and password are required' });
    }
    
    try {
      // Create user - this generates a verification token automatically
      const user = await createUser(input);
      
      // Send verification email asynchronously (don't wait for it to complete)
      // The email service handles errors gracefully, so signup succeeds even if email fails
      // Use frontend URL from config (or pass undefined to use default)
      EmailService.sendVerificationEmail(
        user.email,
        user.fullName,
        user.verificationToken!,
        user.verificationCode!,
        undefined, // Will use FRONTEND_URL from config
      ).catch((error) => {
        console.error('Failed to send verification email (non-blocking):', error);
      });
      
      res.status(201).json({ success: true, data: user });
    } catch (error) {
      // Handle duplicate email error - MySQL returns error code 1062 for duplicate entry
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      // Check if it's a duplicate email error (MySQL error code 1062 or unique constraint violation)
      if (errorMessage.includes('Duplicate entry') || 
          errorMessage.includes('ER_DUP_ENTRY') ||
          errorMessage.includes('UNIQUE constraint') ||
          errorMessage.includes('email')) {
        return res.status(409).json({ 
          success: false, 
          message: 'Email address is already taken' 
        });
      }
      
      // Re-throw other errors to be handled by asyncHandler
      throw error;
    }
  }),
);

/**
 * User login endpoint (email/username + password).
 * Request body: { identifier: string, password: string }
 */
userRouter.post(
  '/auth/login',
  asyncHandler(async (req, res) => {
    const identifier = (req.body.identifier as string | undefined) ?? '';
    const password = (req.body.password as string | undefined) ?? '';

    try {
      const user = await verifyUserCredentials(identifier, password);
      res.json({ success: true, data: user });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Invalid username or password';
      // Use 401 for auth failures, 403 for verification-related blocks.
      const status = message.toLowerCase().includes('verify your email') ? 403 : 401;
      res.status(status).json({ success: false, message });
    }
  }),
);

/**
 * Change password endpoint.
 * Request body: { currentPassword: string, newPassword: string }
 */
userRouter.post(
  '/:id/change-password',
  asyncHandler(async (req, res) => {
    const userId = req.params.id;
    const currentPassword = req.body.currentPassword as string | undefined;
    const newPassword = req.body.newPassword as string | undefined;

    try {
      await changeUserPassword(userId, currentPassword ?? '', newPassword ?? '');
      res.json({ success: true, message: 'Password updated successfully' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to update password';
      res.status(400).json({ success: false, message });
    }
  }),
);

userRouter.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    const input = {
      fullName: req.body.fullName,
      username: req.body.username,
      phoneNumber: req.body.phoneNumber,
      gender: req.body.gender,
      dateOfBirth: req.body.dateOfBirth ? new Date(req.body.dateOfBirth) : null,
      avatarUrl: req.body.avatarUrl,
    };
    const user = await updateUser(req.params.id, input);
    res.json({ success: true, data: user });
  }),
);

userRouter.post(
  '/:id/avatar',
  avatarUpload.single('avatar'),
  asyncHandler(async (req, res) => {
    try {
      const file = req.file;
      if (file == null) {
        return res.status(400).json({ success: false, message: 'Avatar file is required' });
      }

      let url: string;
      if (isSupabaseStorageEnabled()) {
        const ext = path.extname(file.originalname) || '.jpg';
        const fileName = `${generateId('avatar')}${ext}`;
        const contentType =
          file.mimetype && file.mimetype.startsWith('image/') ? file.mimetype : 'image/jpeg';
        const { publicUrl } = await uploadToSupabaseStorage({
          subKey: `avatars/${fileName}`,
          buffer: file.buffer,
          contentType,
        });
        url = publicUrl;
      } else if (isCloudinaryUploadsEnabled()) {
        const ext = path.extname(file.originalname) || '.jpg';
        const fileName = `${generateId('avatar')}${ext}`;
        const { secureUrl } = await uploadImageBuffer({
          subFolder: 'avatars',
          fileName,
          buffer: file.buffer,
        });
        url = secureUrl;
      } else {
        // Prefer PUBLIC_API_BASE_URL so stored avatar URLs always use the canonical
        // public host (Railway, etc.) instead of an internal proxy hostname.
        const origin =
          config.publicApiBaseUrl.trim().length > 0
            ? config.publicApiBaseUrl
            : `${req.protocol}://${req.get('host') ?? 'localhost:4000'}`;
        url = `${origin}/uploads/avatars/${file.filename}`;
      }

      await updateUser(req.params.id, { avatarUrl: url });
      res.json({ success: true, data: { url } });
    } catch (error) {
      console.error('Avatar upload error:', error);
      res.status(500).json({ success: false, message: error instanceof Error ? error.message : 'Failed to upload avatar' });
    }
  }),
);

/**
 * Email verification endpoint.
 * Users click the verification link in their email, which calls this endpoint.
 * Verifies the token and marks the user's email as verified.
 */
userRouter.get(
  '/verify-email',
  asyncHandler(async (req, res) => {
    const token = (req.query.token as string | undefined) ?? '';
    // Set by links in transactional email so webmail opens a real page (not JSON).
    const emailLanding = req.query.ui === '1' || req.query.source === 'email';

    if (!token.trim()) {
      if (emailLanding) {
        return res
          .status(400)
          .type('html')
          .send(
            buildVerifyEmailLandingHtml(
              false,
              'This verification link is missing a token. Request a new email from the app.',
            ),
          );
      }
      return res.status(400).json({
        success: false,
        message: 'Verification token is required',
      });
    }

    try {
      const user = await verifyUserEmail(token);
      if (emailLanding) {
        return res
          .status(200)
          .type('html')
          .send(
            buildVerifyEmailLandingHtml(
              true,
              'You are all set. You can sign in on your phone or the website.',
            ),
          );
      }
      res.json({
        success: true,
        message: 'Email verified successfully',
        data: user,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to verify email';
      if (emailLanding) {
        return res.status(400).type('html').send(buildVerifyEmailLandingHtml(false, message));
      }
      res.status(400).json({
        success: false,
        message,
      });
    }
  }),
);

/**
 * Email verification by code endpoint.
 * Allows users to verify their email by entering a 6-character code instead of clicking a link.
 */
userRouter.post(
  '/verify-email-code',
  asyncHandler(async (req, res) => {
    const code = req.body.code as string;
    
    if (!code || code.trim().length === 0) {
      return res.status(400).json({ 
        success: false, 
        message: 'Verification code is required' 
      });
    }

    try {
      const user = await verifyUserEmailByCode(code.trim().toUpperCase());
      res.json({ 
        success: true, 
        message: 'Email verified successfully',
        data: user 
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Invalid or expired verification code';
      res.status(400).json({ 
        success: false, 
        message 
      });
    }
  }),
);/**
 * Resend verification email endpoint.
 * Allows users to request a new verification email if they didn't receive the first one
 * or if their token expired.
 */
userRouter.post(
  '/:id/resend-verification',
  asyncHandler(async (req, res) => {
    const userId = req.params.id;
    
    try {
      // Generate new verification token and code
      const { token, code } = await resendVerificationToken(userId);
      
      // Get user to send email
      const user = await findUserById(userId);
      if (!user) {
        return res.status(404).json({ 
          success: false, 
          message: 'User not found' 
        });
      }      // Send verification email using frontend URL from config
      await EmailService.sendVerificationEmail(
        user.email,
        user.fullName,
        token,
        code,
        undefined, // Will use FRONTEND_URL from config
      );

      res.json({ 
        success: true, 
        message: 'Verification email sent successfully' 
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to resend verification email';
      res.status(500).json({ 
        success: false, 
        message 
      });
    }
  }),
);
