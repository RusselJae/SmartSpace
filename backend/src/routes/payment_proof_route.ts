import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { paymentProofsDir } from '../utils/uploads';
import { asyncHandler } from '../utils/async_handler';
import { uploadPaymentProof } from '../services/order_service';

export const paymentProofRouter = Router();

// Configure multer for payment proof uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Create order-specific folder for organization
    const orderId = (req.body.orderId as string) || 'default';
    const sanitizedOrderId = orderId
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
    // Generate filename with order ID and timestamp
    const orderId = (req.body.orderId as string) || 'unknown';
    const ext = path.extname(file.originalname);
    const timestamp = Date.now();
    cb(null, `proof_${orderId.substring(0, 8)}_${timestamp}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max file size
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
 * POST /api/payment-proofs/upload
 * Upload a payment proof image for an order
 * 
 * Body (multipart/form-data):
 * - file: The payment proof image (screenshot)
 * - orderId: The order ID this proof is for
 * 
 * Returns:
 * {
 *   success: true,
 *   data: {
 *     fileName: string,
 *     filePath: string,
 *     downloadUrl: string,
 *     orderId: string
 *   }
 * }
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

    // Construct the download URL
    const relativePath = path.relative(paymentProofsDir, req.file.path);
    const downloadUrl = `/uploads/payment-proofs/${relativePath.replace(/\\/g, '/')}`;

    // Update order with payment proof URL
    await uploadPaymentProof(orderId, downloadUrl);

    res.json({
      success: true,
      data: {
        fileName: req.file.originalname,
        filePath: relativePath.replace(/\\/g, '/'),
        downloadUrl,
        orderId,
      },
    });
  }),
);




















