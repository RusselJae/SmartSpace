import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { modelsDir } from '../utils/uploads';
import { asyncHandler } from '../utils/async_handler';
import {
  isCloudinaryUploadsEnabled,
  uploadRawBuffer,
  tryDestroyIfCloudinary,
} from '../services/cloudinary_service';
import {
  isSupabaseStorageEnabled,
  uploadToSupabaseStorage,
  tryDeleteSupabaseStorage,
} from '../services/supabase_storage_service';
import { shouldUseMemoryBufferUpload } from '../services/storage_mode';

export const modelRouter = Router();

// Configure multer — memory when uploading to Supabase Storage or Cloudinary, disk otherwise.
const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const productHandle = (req.body.productHandle as string) || 'default';
    const sanitizedHandle =
      productHandle
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
    fileSize: 100 * 1024 * 1024, // 100MB max file size
  },
  fileFilter: (req, file, cb) => {
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
 * data.filePath: disk-relative path, Cloudinary public_id, or Supabase object path
 * data.downloadUrl: /uploads/... | Cloudinary URL | Supabase public URL
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
        ext.toLowerCase() === '.glb'
          ? 'model/gltf-binary'
          : ext.toLowerCase() === '.gltf'
            ? 'model/gltf+json'
            : 'application/octet-stream';
      const { publicUrl, objectKey } = await uploadToSupabaseStorage({
        subKey: `models/${sanitizedHandle}/${fileName}`,
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
      const { secureUrl, publicId } = await uploadRawBuffer({
        subFolder: `models/${sanitizedHandle}`,
        fileName,
        buffer: req.file.buffer,
        mimeType: req.file.mimetype,
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
 */
modelRouter.delete(
  '/:filePath(*)',
  asyncHandler(async (req, res) => {
    const filePath = req.params.filePath;
    const decoded = decodeURIComponent(filePath);
    const fullPath = path.join(modelsDir, filePath);
    const resolvedPath = path.resolve(fullPath);
    const resolvedModelsDir = path.resolve(modelsDir);
    const isUnderModelsDir = resolvedPath.startsWith(resolvedModelsDir);

    if (isUnderModelsDir && fs.existsSync(fullPath)) {
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

    if (!isUnderModelsDir && !isCloudinaryUploadsEnabled() && !isSupabaseStorageEnabled()) {
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
      const ok = await tryDestroyIfCloudinary(decoded, 'raw');
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
