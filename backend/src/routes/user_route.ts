import path from 'path';

import multer from 'multer';
import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import { listUsers, createUser, updateUser, findUserById, CreateUserInput } from '../services/user_service';
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
    const user = await createUser(input);
    res.status(201).json({ success: true, data: user });
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

