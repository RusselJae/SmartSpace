import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { modelsDir } from '../utils/uploads';
import { asyncHandler } from '../utils/async_handler';

export const modelRouter = Router();

// Configure multer for model uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Create product-specific folder if productHandle is provided
    const productHandle = (req.body.productHandle as string) || 'default';
    const sanitizedHandle = productHandle
      .toLowerCase()
      .replace(/[^a-z0-9-_]/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '') || 'default';
    
    const productDir = path.join(modelsDir, sanitizedHandle);
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
    fileSize: 100 * 1024 * 1024, // 100MB max file size
  },
  fileFilter: (req, file, cb) => {
    // Only allow GLB and GLTF files
    const allowedExts = ['.glb', '.gltf'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedExts.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error(`Invalid file type. Only ${allowedExts.join(', ')} files are allowed.`));
    }
  },
});

/**
 * POST /api/models/upload
 * Upload a 3D model file
 * 
 * Body (multipart/form-data):
 * - file: The GLB/GLTF file
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
modelRouter.post(
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
    // The file is stored at: uploads/models/{productHandle}/{filename}
    // It's served at: /uploads/models/{productHandle}/{filename}
    const relativePath = path.relative(modelsDir, req.file.path);
    const downloadUrl = `/uploads/models/${relativePath.replace(/\\/g, '/')}`;

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
 * DELETE /api/models/:filePath
 * Delete a model file
 * 
 * filePath should be URL-encoded path like: product-handle/filename.glb
 */
modelRouter.delete(
  '/:filePath(*)',
  asyncHandler(async (req, res) => {
    const filePath = req.params.filePath;
    const fullPath = path.join(modelsDir, filePath);

    // Security check: ensure the path is within modelsDir
    const resolvedPath = path.resolve(fullPath);
    const resolvedModelsDir = path.resolve(modelsDir);
    if (!resolvedPath.startsWith(resolvedModelsDir)) {
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

