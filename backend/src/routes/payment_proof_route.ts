import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { paymentProofsDir } from '../utils/uploads';
import { asyncHandler } from '../utils/async_handler';
import { uploadPaymentProof } from '../services/order_service';
import { isCloudinaryUploadsEnabled, uploadImageBuffer } from '../services/cloudinary_service';
import { isSupabaseStorageEnabled, uploadToSupabaseStorage } from '../services/supabase_storage_service';
import { shouldUseMemoryBufferUpload } from '../services/storage_mode';

export const paymentProofRouter = Router();

const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const orderId = (req.body.orderId as string) || 'default';
    const sanitizedOrderId =
      orderId
        .toLowerCase()
        .replace(/[^a-z0-9-_]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '') || 'default';

    const orderDir = path.join(paymentProofsDir, sanitizedOrderId);
    if (!fs.existsSync(orderDir)) {
      fs.mkdirSync(orderDir, { recursive: true });
    }
    cb(null, orderDir);
  },
  filename: (req, file, cb) => {
    const orderId = (req.body.orderId as string) || 'unknown';
    const ext = path.extname(file.originalname);
    const timestamp = Date.now();
    cb(null, `proof_${orderId.substring(0, 8)}_${timestamp}${ext}`);
  },
});

const upload = multer({
  storage: shouldUseMemoryBufferUpload() ? multer.memoryStorage() : diskStorage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max file size
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
 * POST /api/payment-proofs/upload
 */
paymentProofRouter.post(
  '/upload',
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file uploaded',
      });
    }

    const orderId = req.body.orderId as string;
    if (!orderId) {
      return res.status(400).json({
        success: false,
        message: 'orderId is required',
      });
    }

    const sanitizedOrderId =
      orderId
        .toLowerCase()
        .replace(/[^a-z0-9-_]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '') || 'default';

    let downloadUrl: string;
    let relativePath: string;

    const ext = path.extname(req.file.originalname);
    const timestamp = Date.now();
    const fileName = `proof_${orderId.substring(0, 8)}_${timestamp}${ext}`;

    if (isSupabaseStorageEnabled()) {
      const contentType =
        req.file.mimetype && req.file.mimetype.startsWith('image/')
          ? req.file.mimetype
          : 'application/octet-stream';
      const { publicUrl, objectKey } = await uploadToSupabaseStorage({
        subKey: `payment-proofs/${sanitizedOrderId}/${fileName}`,
        buffer: req.file.buffer,
        contentType,
      });
      downloadUrl = publicUrl;
      relativePath = objectKey;
    } else if (isCloudinaryUploadsEnabled()) {
      const { secureUrl, publicId } = await uploadImageBuffer({
        subFolder: `payment-proofs/${sanitizedOrderId}`,
        fileName,
        buffer: req.file.buffer,
      });

      downloadUrl = secureUrl;
      relativePath = publicId;
    } else {
      relativePath = path.relative(paymentProofsDir, req.file.path).replace(/\\/g, '/');
      downloadUrl = `/uploads/payment-proofs/${relativePath}`;
    }

    await uploadPaymentProof(orderId, downloadUrl);

    res.json({
      success: true,
      data: {
        fileName: req.file.originalname,
        filePath: relativePath,
        downloadUrl,
        orderId,
      },
    });
  }),
);
