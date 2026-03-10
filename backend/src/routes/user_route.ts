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
  CreateUserInput 
} from '../services/user_service';
import { EmailService } from '../services/email_service';
import { avatarsDir, ensureUploadsDirectories } from '../utils/uploads';
import { generateId } from '../utils/id_generator';

export const userRouter = Router();

ensureUploadsDirectories();

const avatarStorage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    cb(null, avatarsDir);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${generateId('avatar')}${ext}`);
  },
});

const avatarUpload = multer({
  storage: avatarStorage,
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
      username: req.body.username,
      phoneNumber: req.body.phoneNumber,
      gender: req.body.gender,
    };
    if (!input.email || !input.fullName) {
      return res.status(400).json({ success: false, message: 'Email and full name are required' });
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
      const host = req.get('host') ?? 'localhost:4000';
      const protocol = req.protocol;
      const url = `${protocol}://${host}/uploads/avatars/${file.filename}`;
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
    const token = req.query.token as string;
    
    if (!token) {
      return res.status(400).json({ 
        success: false, 
        message: 'Verification token is required' 
      });
    }

    try {
      const user = await verifyUserEmail(token);
      res.json({ 
        success: true, 
        message: 'Email verified successfully',
        data: user 
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to verify email';
      res.status(400).json({ 
        success: false, 
        message 
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
