import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { asyncHandler } from '../utils/async_handler';
import { uploadsRoot } from '../utils/uploads';
import { isCloudinaryUploadsEnabled, uploadImageBuffer, uploadRawBuffer } from '../services/cloudinary_service';
import { isSupabaseStorageEnabled, uploadToSupabaseStorage } from '../services/supabase_storage_service';
import { shouldUseMemoryBufferUpload } from '../services/storage_mode';

export const reviewMediaRouter = Router();

const reviewMediaDir = path.join(uploadsRoot, 'review-media');

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    if (!fs.existsSync(reviewMediaDir)) {
      fs.mkdirSync(reviewMediaDir, { recursive: true });
    }
    cb(null, reviewMediaDir);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '';
    const base = path.basename(file.originalname, ext).replace(/[^a-zA-Z0-9-_]/g, '_').slice(0, 60);
    cb(null, `${base}_${Date.now()}${ext}`);
  },
});

const upload = multer({
  storage: shouldUseMemoryBufferUpload() ? multer.memoryStorage() : storage,
  limits: { fileSize: 30 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const imageExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
    const videoExts = ['.mp4', '.mov', '.webm'];
    if (imageExts.includes(ext) || videoExts.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Only image (jpg, png, webp, gif) or video (mp4, mov, webm) files are allowed'));
    }
  },
});

reviewMediaRouter.post(
  '/upload',
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'file is required' });
    }
    const ext = path.extname(req.file.originalname).toLowerCase();
    const isVideo = ['.mp4', '.mov', '.webm'].includes(ext);
    const fileName = path.basename(
      shouldUseMemoryBufferUpload() ? req.file.originalname : req.file.path,
    );

    let url: string;
    if (isSupabaseStorageEnabled() && req.file.buffer) {
      const { publicUrl } = await uploadToSupabaseStorage({
        subKey: `review-media/${fileName}`,
        buffer: req.file.buffer,
        contentType: req.file.mimetype || (isVideo ? 'video/mp4' : 'image/jpeg'),
      });
      url = publicUrl;
    } else if (isCloudinaryUploadsEnabled() && req.file.buffer) {
      if (isVideo) {
        const { secureUrl } = await uploadRawBuffer({
          subFolder: 'review-media',
          fileName,
          buffer: req.file.buffer,
        });
        url = secureUrl;
      } else {
        const { secureUrl } = await uploadImageBuffer({
          subFolder: 'review-media',
          fileName,
          buffer: req.file.buffer,
        });
        url = secureUrl;
      }
    } else {
      const relative = path.relative(uploadsRoot, req.file.path).replace(/\\/g, '/');
      url = `/uploads/${relative}`;
    }

    res.status(201).json({
      success: true,
      data: {
        url,
        type: isVideo ? 'video' : 'image',
      },
    });
  }),
);
