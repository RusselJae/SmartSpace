import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { imagesDir } from '../utils/uploads';
import { asyncHandler } from '../utils/async_handler';
import {
  isCloudinaryUploadsEnabled,
  uploadImageBuffer,
  tryDestroyIfCloudinary,
} from '../services/cloudinary_service';
import {
  isSupabaseStorageEnabled,
  uploadToSupabaseStorage,
  tryDeleteSupabaseStorage,
} from '../services/supabase_storage_service';
import { shouldUseMemoryBufferUpload } from '../services/storage_mode';

export const imageRouter = Router();

const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const productHandle = (req.body.productHandle as string) || 'default';
    const sanitizedHandle =
      productHandle
        .toLowerCase()
        .replace(/[^a-z0-9-_]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '') || 'default';

    const productDir = path.join(imagesDir, sanitizedHandle);
    if (!fs.existsSync(productDir)) {
      fs.mkdirSync(productDir, { recursive: true });
    }
    cb(null, productDir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const name = path
      .basename(file.originalname, ext)
      .replace(/[^a-zA-Z0-9-_]/g, '_')
      .substring(0, 100);
    const timestamp = Date.now();
    cb(null, `${name}_${timestamp}${ext}`);
  },
});

const upload = multer({
  storage: shouldUseMemoryBufferUpload() ? multer.memoryStorage() : diskStorage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max file size for images
  },
  fileFilter: (req, file, cb) => {
    const allowedExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedExts.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error(`Invalid file type. Only ${allowedExts.join(', ')} images are allowed.`));
    }
  },
});

/**
 * POST /api/images/upload
 */
imageRouter.post(
  '/upload',
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file uploaded',
      });
    }

    const productHandle = (req.body.productHandle as string) || 'default';
    const sanitizedHandle =
      productHandle
        .toLowerCase()
        .replace(/[^a-z0-9-_]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '') || 'default';

    const ext = path.extname(req.file.originalname);
    const name = path
      .basename(req.file.originalname, ext)
      .replace(/[^a-zA-Z0-9-_]/g, '_')
      .substring(0, 100);
    const timestamp = Date.now();
    const fileName = `${name}_${timestamp}${ext}`;

    if (isSupabaseStorageEnabled()) {
      const contentType =
        req.file.mimetype && req.file.mimetype.startsWith('image/')
          ? req.file.mimetype
          : 'application/octet-stream';
      const { publicUrl, objectKey } = await uploadToSupabaseStorage({
        subKey: `images/${sanitizedHandle}/${fileName}`,
        buffer: req.file.buffer,
        contentType,
      });
      return res.json({
        success: true,
        data: {
          fileName: req.file.originalname,
          filePath: objectKey,
          downloadUrl: publicUrl,
        },
      });
    }

    if (isCloudinaryUploadsEnabled()) {
      const { secureUrl, publicId } = await uploadImageBuffer({
        subFolder: `images/${sanitizedHandle}`,
        fileName,
        buffer: req.file.buffer,
      });

      return res.json({
        success: true,
        data: {
          fileName: req.file.originalname,
          filePath: publicId,
          downloadUrl: secureUrl,
        },
      });
    }

    const relativePath = path.relative(imagesDir, req.file.path);
    const downloadUrl = `/uploads/images/${relativePath.replace(/\\/g, '/')}`;

    res.json({
      success: true,
      data: {
        fileName: req.file.originalname,
        filePath: relativePath.replace(/\\/g, '/'),
        downloadUrl,
      },
    });
  }),
);

/**
 * DELETE /api/images/:filePath
 */
imageRouter.delete(
  '/:filePath(*)',
  asyncHandler(async (req, res) => {
    const filePath = req.params.filePath;
    const decoded = decodeURIComponent(filePath);
    const fullPath = path.join(imagesDir, filePath);
    const resolvedPath = path.resolve(fullPath);
    const resolvedImagesDir = path.resolve(imagesDir);
    const isUnderImagesDir = resolvedPath.startsWith(resolvedImagesDir);

    if (isUnderImagesDir && fs.existsSync(fullPath)) {
      try {
        fs.unlinkSync(fullPath);
        return res.json({
          success: true,
          message: 'File deleted successfully',
        });
      } catch (error) {
        return res.status(500).json({
          success: false,
          message: 'Failed to delete file',
          error: error instanceof Error ? error.message : 'Unknown error',
        });
      }
    }

    if (!isUnderImagesDir && !isCloudinaryUploadsEnabled() && !isSupabaseStorageEnabled()) {
      return res.status(403).json({
        success: false,
        message: 'Invalid file path',
      });
    }

    if (isSupabaseStorageEnabled()) {
      const ok = await tryDeleteSupabaseStorage(decoded);
      if (ok) {
        return res.json({
          success: true,
          message: 'File deleted successfully',
        });
      }
    }

    if (isCloudinaryUploadsEnabled()) {
      const ok = await tryDestroyIfCloudinary(decoded, 'image');
      if (ok) {
        return res.json({
          success: true,
          message: 'File deleted successfully',
        });
      }
    }

    return res.status(404).json({
      success: false,
      message: 'File not found',
    });
  }),
);
