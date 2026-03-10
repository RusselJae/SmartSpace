import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { imagesDir } from '../utils/uploads';
import { asyncHandler } from '../utils/async_handler';

export const imageRouter = Router();

// Configure multer for image uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Create product-specific folder if productHandle is provided
    const productHandle = (req.body.productHandle as string) || 'default';
    const sanitizedHandle = productHandle
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
    // Keep original filename but sanitize it
    const ext = path.extname(file.originalname);
    const name = path.basename(file.originalname, ext)
      .replace(/[^a-zA-Z0-9-_]/g, '_')
      .substring(0, 100); // Limit length
    const timestamp = Date.now();
    cb(null, `${name}_${timestamp}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max file size for images
  },
  fileFilter: (req, file, cb) => {
    // Only allow image files
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
 * Upload a product image file
 * 
 * Body (multipart/form-data):
 * - file: The image file
 * - productHandle: Optional product identifier for folder organization
 * 
 * Returns:
 * {
 *   success: true,
 *   data: {
 *     fileName: string,
 *     filePath: string,
 *     downloadUrl: string
 *   }
 * }
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

    // Construct the download URL
    // The file is stored at: uploads/images/{productHandle}/{filename}
    // It's served at: /uploads/images/{productHandle}/{filename}
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
 * Delete an image file
 * 
 * filePath should be URL-encoded path like: product-handle/filename.jpg
 */
imageRouter.delete(
  '/:filePath(*)',
  asyncHandler(async (req, res) => {
    const filePath = req.params.filePath;
    const fullPath = path.join(imagesDir, filePath);

    // Security check: ensure the path is within imagesDir
    const resolvedPath = path.resolve(fullPath);
    const resolvedImagesDir = path.resolve(imagesDir);
    if (!resolvedPath.startsWith(resolvedImagesDir)) {
      return res.status(403).json({
        success: false,
        message: 'Invalid file path',
      });
    }

    try {
      if (fs.existsSync(fullPath)) {
        fs.unlinkSync(fullPath);
        res.json({
          success: true,
          message: 'File deleted successfully',
        });
      } else {
        res.status(404).json({
          success: false,
          message: 'File not found',
        });
      }
    } catch (error) {
      res.status(500).json({
        success: false,
        message: 'Failed to delete file',
        error: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }),
);

