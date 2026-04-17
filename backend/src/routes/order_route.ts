import path from 'path';
import fs from 'fs';
import multer from 'multer';
import { Router } from 'express';
import { RowDataPacket } from 'mysql2';
import { z } from 'zod';
import { getPool } from '../config/database';
import { asyncHandler } from '../utils/async_handler';
import { madeToOrderDir, validIdsDir } from '../utils/uploads';
import { isCloudinaryUploadsEnabled, uploadImageBuffer } from '../services/cloudinary_service';
import { isSupabaseStorageEnabled, uploadToSupabaseStorage } from '../services/supabase_storage_service';
import { shouldUseMemoryBufferUpload } from '../services/storage_mode';
import {
  listOrders,
  createOrder,
  createMadeToOrderOrderFromRequest,
  updateOrderStatus,
  confirmPayment,
  getOrderById,
  updateOrderValidIdProofUrl,
  CreateOrderInput,
} from '../services/order_service';
import { createPaymongoCheckoutSession } from '../services/paymongo_service';
import { config } from '../config/env';
import { findUserById } from '../services/user_service';
import { getLegalContent } from '../services/legal_content_service';
import { logAdminActivity } from '../services/admin_activity_log_service';
import { buildUpdatedOrderInvoiceHtml } from '../services/order_invoice_service';

const validIdStorage = multer.diskStorage({
  destination: (req, _file, cb) => {
    const orderId = (req.params.id as string) || 'default';
    const sanitized = orderId.replace(/[^a-z0-9-_]/gi, '-');
    const dir = path.join(validIdsDir, sanitized);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const orderId = (req.params.id as string) || 'unknown';
    const ext = path.extname(file.originalname);
    cb(null, `valid_id_${orderId.substring(0, 8)}_${Date.now()}${ext}`);
  },
});

const validIdUpload = multer({
  storage: shouldUseMemoryBufferUpload() ? multer.memoryStorage() : validIdStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const allowed = ['.jpg', '.jpeg', '.png', '.webp'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type'));
    }
  },
});

// ---------------------------------------------------------------------------
// Made-to-order attachments (no order row yet; use requestRef from checkout)
// ---------------------------------------------------------------------------
const mtoStorage = multer.diskStorage({
  destination: (req, _file, cb) => {
    const requestRef = (req.params.requestRef as string) || 'default';
    const sanitized = requestRef.replace(/[^a-z0-9-_]/gi, '-');
    const dir = path.join(madeToOrderDir, sanitized);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `mto_${Date.now()}${ext}`);
  },
});

const mtoUpload = multer({
  storage: shouldUseMemoryBufferUpload() ? multer.memoryStorage() : mtoStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const allowed = ['.jpg', '.jpeg', '.png', '.webp'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type'));
    }
  },
});

const statusSchema = z.object({
  status: z.string().min(1),
});

export const orderRouter = Router();

const ensureMadeToOrderRequestsTable = async (): Promise<void> => {
  const pool = getPool();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS made_to_order_requests (
      id VARCHAR(32) NOT NULL PRIMARY KEY,
      request_ref VARCHAR(64) NOT NULL UNIQUE,
      user_id VARCHAR(64) NOT NULL,
      user_name VARCHAR(255) NOT NULL,
      item_name VARCHAR(255) NOT NULL,
      preferred_size VARCHAR(255) NULL,
      materials VARCHAR(255) NULL,
      notes TEXT NULL,
      down_payment_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
      valid_id_url TEXT NULL,
      reference_urls_json JSON NULL,
      status VARCHAR(32) NOT NULL DEFAULT 'pending_review',
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);
  const alters = [
    `ALTER TABLE made_to_order_requests ADD COLUMN quoted_total DECIMAL(12,2) NULL`,
    `ALTER TABLE made_to_order_requests ADD COLUMN quoted_downpayment DECIMAL(12,2) NULL`,
    `ALTER TABLE made_to_order_requests ADD COLUMN quoted_remaining DECIMAL(12,2) NULL`,
    `ALTER TABLE made_to_order_requests ADD COLUMN admin_message TEXT NULL`,
    `ALTER TABLE made_to_order_requests ADD COLUMN order_id VARCHAR(50) NULL`,
  ];
  for (const sql of alters) {
    try {
      await pool.query(sql);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (!msg.includes('Duplicate column')) {
        console.warn('made_to_order_requests alter:', msg);
      }
    }
  }
};

orderRouter.get(
  '/:id/invoice',
  asyncHandler(async (req, res) => {
    const orderId = req.params.id;
    const normalizedUserId =
      typeof req.query.userId === 'string' && req.query.userId.trim().length > 0
        ? req.query.userId.trim()
        : null;

    const order = await getOrderById(orderId);
    if (!order) {
      return res.status(404).type('html').send('<h1>Order not found</h1>');
    }
    if (normalizedUserId != null && order.userId !== normalizedUserId) {
      return res.status(403).type('html').send('<h1>Forbidden</h1>');
    }

    const invoice = await buildUpdatedOrderInvoiceHtml(orderId);
    res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${invoice.invoiceTitle}</title>
</head>
<body style="margin:0;padding:18px;background:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;color:#111827;">
  <div style="max-width:920px;margin:0 auto 18px auto;display:flex;justify-content:flex-end;">
    <button onclick="window.print()" style="border:1px solid #d1d5db;background:#fff;color:#111827;border-radius:999px;padding:10px 16px;font-weight:700;cursor:pointer;">
      Print / Save PDF
    </button>
  </div>
  <div style="max-width:920px;margin:0 auto;background:#fff;border-radius:20px;padding:20px;box-shadow:0 10px 32px rgba(0,0,0,.08);">
    ${invoice.bodyHtml}
  </div>
</body>
</html>`);
  }),
);

orderRouter.get(
  '/:id/invoice-data',
  asyncHandler(async (req, res) => {
    const orderId = req.params.id;
    const normalizedUserId =
      typeof req.query.userId === 'string' && req.query.userId.trim().length > 0
        ? req.query.userId.trim()
        : null;

    const order = await getOrderById(orderId);
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }
    if (normalizedUserId != null && order.userId !== normalizedUserId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }

    const invoice = await buildUpdatedOrderInvoiceHtml(orderId);
    return res.json({
      success: true,
      data: {
        orderId,
        invoiceNumber: invoice.invoiceNumber,
        invoiceTitle: invoice.invoiceTitle,
        version: invoice.version,
        totalBalanceDue: invoice.totalBalanceDue,
        totalLateFees: invoice.totalLateFees,
        depositPaid: invoice.depositPaid,
        paymentEvents: invoice.paymentEvents.map((e) => ({
          id: e.id,
          eventType: e.event_type,
          amount: Number(e.amount),
          eventTime: e.event_time,
        })),
        lateFeeEvents: invoice.lateFeeEvents.map((e) => ({
          id: e.id,
          feeDate: e.fee_date,
          amount: Number(e.amount),
          createdAt: e.created_at,
        })),
        order: {
          userName: order.userName,
          totalAmount: order.totalAmount,
          status: order.status,
          createdAt: order.createdAt,
          updatedAt: order.updatedAt,
          shippingAddress: order.shippingAddress,
          productIds: order.productIds,
        },
      },
    });
  }),
);

orderRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const orders = await listOrders();
    res.json({ success: true, data: orders });
  }),
);

orderRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const input: CreateOrderInput = {
      userId: req.body.userId,
      userName: req.body.userName,
      productIds: req.body.productIds ?? [],
      totalAmount: Number(req.body.totalAmount),
      shippingAddress: req.body.shippingAddress ?? {},
      status: req.body.status,
    };
    if (!input.userId || !input.userName || !input.productIds || input.productIds.length === 0) {
      return res.status(400).json({ success: false, message: 'userId, userName, and productIds are required' });
    }
    const user = await findUserById(input.userId);
    const terms = await getLegalContent('terms');
    if (!user || (user.termsVersionAccepted ?? 0) < terms.version) {
      return res.status(403).json({
        success: false,
        message: 'Please accept the latest Terms and Conditions before placing an order.',
      });
    }
    const order = await createOrder(input);
    res.status(201).json({ success: true, data: order });
  }),
);

/**
 * POST /api/orders/:id/paymongo-checkout
 * Creates a PayMongo Checkout Session (server-side). Returns checkoutUrl for the app to open.
 * Body: { userId: string, amountPesos?: number } — must match order owner.
 */
orderRouter.post(
  '/made-to-order/paymongo-checkout',
  asyncHandler(async (req, res) => {
    const amountPesosRaw = Number(req.body.amountPesos);
    const itemNameRaw = String(req.body.itemName ?? '').trim();

    if (!Number.isFinite(amountPesosRaw)) {
      return res.status(400).json({ success: false, message: 'amountPesos is required' });
    }
    // Made-to-order policy: required down payment range.
    if (amountPesosRaw < 3000 || amountPesosRaw > 5000) {
      return res.status(400).json({
        success: false,
        message: 'Down payment must be between ₱3,000 and ₱5,000.',
      });
    }

    const requestRef = `mto_${Date.now()}`;
    const appendRequestIdToUrl = (baseUrl: string, id: string): string => {
      const hasQuery = baseUrl.includes('?');
      return hasQuery
        ? `${baseUrl}&mtoRequestId=${encodeURIComponent(id)}`
        : `${baseUrl}?mtoRequestId=${encodeURIComponent(id)}`;
    };

    const successUrl = appendRequestIdToUrl(config.paymongo.successUrl, requestRef);
    const cancelUrl = appendRequestIdToUrl(config.paymongo.cancelUrl, requestRef);
    const safeItemName = itemNameRaw.length > 0 ? itemNameRaw : 'Custom furniture request';

    try {
      const session = await createPaymongoCheckoutSession({
        orderId: requestRef,
        amountPesos: amountPesosRaw,
        // Keep branding neutral per request.
        description: `Made-to-order down payment: ${safeItemName}`,
        successUrl,
        cancelUrl,
      });
      return res.json({
        success: true,
        data: {
          checkoutUrl: session.checkoutUrl,
          checkoutSessionId: session.checkoutSessionId,
          requestRef,
        },
      });
    } catch (e) {
      const message = e instanceof Error ? e.message : 'PayMongo failed';
      console.error('made-to-order paymongo-checkout:', e);
      return res.status(503).json({ success: false, message });
    }
  }),
);

orderRouter.post(
  '/made-to-order/requests',
  asyncHandler(async (req, res) => {
    const userId = String(req.body.userId ?? '').trim();
    const userName = String(req.body.userName ?? '').trim();
    const itemName = String(req.body.itemName ?? '').trim();
    const preferredSize = String(req.body.preferredSize ?? '').trim();
    const materials = String(req.body.materials ?? '').trim();
    const notes = String(req.body.notes ?? '').trim();

    if (!userId || !userName || !itemName) {
      return res.status(400).json({
        success: false,
        message: 'userId, userName, and itemName are required',
      });
    }

    await ensureMadeToOrderRequestsTable();
    const pool = getPool();
    const id = `mto_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const requestRef = id;
    await pool.query(
      `INSERT INTO made_to_order_requests
         (id, request_ref, user_id, user_name, item_name, preferred_size, materials, notes, down_payment_amount, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending_review')`,
      [id, requestRef, userId, userName, itemName, preferredSize || null, materials || null, notes || null, 0],
    );

    return res.status(201).json({
      success: true,
      data: { id, requestRef },
    });
  }),
);

orderRouter.get(
  '/made-to-order/requests',
  asyncHandler(async (req, res) => {
    await ensureMadeToOrderRequestsTable();
    const pool = getPool();
    const userIdFilter =
      typeof req.query.userId === 'string' && req.query.userId.trim().length > 0
        ? req.query.userId.trim()
        : null;
    const whereSql = userIdFilter ? 'WHERE user_id = ?' : '';
    const params: string[] = userIdFilter ? [userIdFilter] : [];
    const [rows] = await pool.query<RowDataPacket[]>(
      `SELECT id, request_ref AS requestRef, user_id AS userId, user_name AS userName,
              item_name AS itemName, preferred_size AS preferredSize, materials, notes,
              down_payment_amount AS downPaymentAmount, valid_id_url AS validIdUrl,
              reference_urls_json AS referenceUrlsJson, status,
              quoted_total AS quotedTotal, quoted_downpayment AS quotedDownpayment,
              quoted_remaining AS quotedRemaining, admin_message AS adminMessage,
              order_id AS orderId,
              created_at AS createdAt, updated_at AS updatedAt
       FROM made_to_order_requests
       ${whereSql}
       ORDER BY created_at DESC`,
      params,
    );
    return res.json({ success: true, data: rows });
  }),
);

/**
 * PATCH /api/orders/made-to-order/requests/:requestId/quote
 * Admin sets quoted totals; request moves to `quoted`.
 */
orderRouter.patch(
  '/made-to-order/requests/:requestId/quote',
  asyncHandler(async (req, res) => {
    const requestId = req.params.requestId;
    const quotedTotal = Number(req.body.quotedTotal);
    const quotedDownpayment = Number(req.body.quotedDownpayment);
    const quotedRemaining = Number(req.body.quotedRemaining);
    const adminMessage =
      req.body.adminMessage != null ? String(req.body.adminMessage).trim() : null;

    if (
      !Number.isFinite(quotedTotal) ||
      !Number.isFinite(quotedDownpayment) ||
      !Number.isFinite(quotedRemaining)
    ) {
      return res.status(400).json({
        success: false,
        message: 'quotedTotal, quotedDownpayment, and quotedRemaining are required numbers',
      });
    }
    if (quotedTotal < 0 || quotedDownpayment < 0 || quotedRemaining < 0) {
      return res.status(400).json({ success: false, message: 'Amounts must be non-negative' });
    }
    const sum = quotedDownpayment + quotedRemaining;
    if (Math.abs(sum - quotedTotal) > 0.05) {
      return res.status(400).json({
        success: false,
        message: 'Down payment + remaining balance must equal quoted total',
      });
    }

    await ensureMadeToOrderRequestsTable();
    const pool = getPool();
    const [existing] = await pool.query<RowDataPacket[]>(
      `SELECT id, status FROM made_to_order_requests WHERE id = ? LIMIT 1`,
      [requestId],
    );
    if (existing.length === 0) {
      return res.status(404).json({ success: false, message: 'Request not found' });
    }
    const st = String(existing[0].status ?? '');
    if (st === 'declined' || st === 'order_created') {
      return res.status(400).json({ success: false, message: 'Request cannot be quoted in its current state' });
    }

    await pool.query(
      `UPDATE made_to_order_requests
       SET quoted_total = ?, quoted_downpayment = ?, quoted_remaining = ?,
           admin_message = COALESCE(?, admin_message), status = 'quoted', updated_at = NOW()
       WHERE id = ?`,
      [quotedTotal, quotedDownpayment, quotedRemaining, adminMessage, requestId],
    );
    const adminId = req.body.adminId != null ? String(req.body.adminId).trim() : '';
    if (adminId.length > 0) {
      await logAdminActivity({
        adminId,
        action: 'made_to_order_quoted',
        entityType: 'made_to_order_request',
        entityId: requestId,
        details: {
          quotedTotal: String(quotedTotal),
          quotedDownpayment: String(quotedDownpayment),
          quotedRemaining: String(quotedRemaining),
        },
      });
    }
    return res.json({ success: true, data: { id: requestId, status: 'quoted' } });
  }),
);

/**
 * PATCH /api/orders/made-to-order/requests/:requestId/decline
 * Admin declines when the build is not feasible.
 */
orderRouter.patch(
  '/made-to-order/requests/:requestId/decline',
  asyncHandler(async (req, res) => {
    const requestId = req.params.requestId;
    const adminMessage =
      req.body.adminMessage != null ? String(req.body.adminMessage).trim() : null;

    await ensureMadeToOrderRequestsTable();
    const pool = getPool();
    const [existing] = await pool.query<RowDataPacket[]>(
      `SELECT id, status FROM made_to_order_requests WHERE id = ? LIMIT 1`,
      [requestId],
    );
    if (existing.length === 0) {
      return res.status(404).json({ success: false, message: 'Request not found' });
    }
    const st = String(existing[0].status ?? '');
    if (st === 'declined' || st === 'order_created') {
      return res.status(400).json({ success: false, message: 'Request is already finalized' });
    }

    await pool.query(
      `UPDATE made_to_order_requests
       SET status = 'declined', admin_message = ?, updated_at = NOW()
       WHERE id = ?`,
      [adminMessage, requestId],
    );
    const adminId = req.body.adminId != null ? String(req.body.adminId).trim() : '';
    if (adminId.length > 0) {
      await logAdminActivity({
        adminId,
        action: 'made_to_order_declined',
        entityType: 'made_to_order_request',
        entityId: requestId,
        details: {
          adminMessage: adminMessage ?? '',
        },
      });
    }
    return res.json({ success: true, data: { id: requestId, status: 'declined' } });
  }),
);

/**
 * POST /api/orders/made-to-order/requests/:requestId/create-order
 * User accepts quote: creates a real order (PayMongo down payment) and links it to the request.
 * Body: { userId, shippingAddress }
 */
orderRouter.post(
  '/made-to-order/requests/:requestId/create-order',
  asyncHandler(async (req, res) => {
    const requestId = req.params.requestId;
    const userId = String(req.body.userId ?? '').trim();
    const shippingAddress = req.body.shippingAddress as Record<string, unknown> | undefined;

    if (!userId || !shippingAddress || typeof shippingAddress !== 'object') {
      return res.status(400).json({
        success: false,
        message: 'userId and shippingAddress are required',
      });
    }
    const user = await findUserById(userId);
    const terms = await getLegalContent('terms');
    if (!user || (user.termsVersionAccepted ?? 0) < terms.version) {
      return res.status(403).json({
        success: false,
        message: 'Please accept the latest Terms and Conditions before creating an order.',
      });
    }

    await ensureMadeToOrderRequestsTable();
    const pool = getPool();
    const [rows] = await pool.query<RowDataPacket[]>(
      `SELECT * FROM made_to_order_requests WHERE id = ? LIMIT 1`,
      [requestId],
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Request not found' });
    }
    const row = rows[0];
    if (String(row.user_id) !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    if (String(row.status) !== 'quoted') {
      return res.status(400).json({
        success: false,
        message: 'Request must be quoted before creating an order',
      });
    }
    if (row.order_id != null && String(row.order_id).length > 0) {
      return res.status(400).json({ success: false, message: 'An order already exists for this request' });
    }

    const quotedTotal = Number(row.quoted_total);
    const quotedDown = Number(row.quoted_downpayment);
    const quotedRem = Number(row.quoted_remaining);
    if (!Number.isFinite(quotedTotal) || !Number.isFinite(quotedDown) || !Number.isFinite(quotedRem)) {
      return res.status(400).json({ success: false, message: 'Invalid quote on this request' });
    }

    try {
      const order = await createMadeToOrderOrderFromRequest({
        userId: String(row.user_id),
        userName: String(row.user_name),
        requestId: String(row.id),
        requestRef: String(row.request_ref),
        itemName: String(row.item_name),
        quotedTotal,
        quotedDownpayment: quotedDown,
        quotedRemaining: quotedRem,
        shippingAddress,
      });

      const validIdUrl = row.valid_id_url != null ? String(row.valid_id_url).trim() : '';
      if (validIdUrl.length > 0) {
        try {
          await updateOrderValidIdProofUrl(order.id, validIdUrl);
        } catch (e) {
          console.warn('Could not copy MTO valid ID to order:', e);
        }
      }

      await pool.query(
        `UPDATE made_to_order_requests SET order_id = ?, status = 'order_created', updated_at = NOW() WHERE id = ?`,
        [order.id, requestId],
      );

      const adminId =
        shippingAddress['adminId'] != null ? String(shippingAddress['adminId']).trim() : '';
      if (adminId.length > 0) {
        await logAdminActivity({
          adminId,
          action: 'made_to_order_order_created',
          entityType: 'made_to_order_request',
          entityId: requestId,
          details: {
            orderId: order.id,
          },
        });
      }

      return res.status(201).json({ success: true, data: { orderId: order.id, order } });
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Failed to create order';
      console.error('create-order from MTO request:', e);
      return res.status(400).json({ success: false, message });
    }
  }),
);

/**
 * POST /api/orders/made-to-order/:requestRef/valid-id
 * multipart: file (image)
 */
orderRouter.post(
  '/made-to-order/:requestRef/valid-id',
  mtoUpload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No file uploaded' });
    }
    const requestRef = req.params.requestRef;
    let downloadUrl: string;
    const sanitized = requestRef.replace(/[^a-z0-9-_]/gi, '-');
    const ext = path.extname(req.file.originalname);
    const fileName = `mto_valid_${Date.now()}${ext}`;
    if (isSupabaseStorageEnabled()) {
      const contentType =
        req.file.mimetype && req.file.mimetype.startsWith('image/')
          ? req.file.mimetype
          : 'application/octet-stream';
      const { publicUrl } = await uploadToSupabaseStorage({
        subKey: `made-to-order/${sanitized}/${fileName}`,
        buffer: req.file.buffer,
        contentType,
      });
      downloadUrl = publicUrl;
    } else if (isCloudinaryUploadsEnabled()) {
      const { secureUrl } = await uploadImageBuffer({
        subFolder: `made-to-order/${sanitized}`,
        fileName,
        buffer: req.file.buffer,
      });
      downloadUrl = secureUrl;
    } else {
      const relative = path.relative(madeToOrderDir, req.file.path);
      downloadUrl = `/uploads/made-to-order/${relative.replace(/\\/g, '/')}`;
    }
    try {
      await ensureMadeToOrderRequestsTable();
      const pool = getPool();
      await pool.query(
        `UPDATE made_to_order_requests
         SET valid_id_url = ?, updated_at = NOW()
         WHERE request_ref = ?`,
        [downloadUrl, requestRef],
      );
    } catch (e) {
      console.warn('Failed to persist made-to-order valid ID URL:', e);
    }
    return res.json({
      success: true,
      data: { downloadUrl, requestRef },
    });
  }),
);

/**
 * POST /api/orders/made-to-order/:requestRef/reference-images
 * multipart: files[] (images)
 */
orderRouter.post(
  '/made-to-order/:requestRef/reference-images',
  mtoUpload.array('files', 8),
  asyncHandler(async (req, res) => {
    const files = req.files as Express.Multer.File[] | undefined;
    if (!files || files.length === 0) {
      return res.status(400).json({ success: false, message: 'No files uploaded' });
    }
    const requestRef = req.params.requestRef;
    const sanitizedRef = requestRef.replace(/[^a-z0-9-_]/gi, '-');
    let downloadUrls: string[];
    if (isSupabaseStorageEnabled()) {
      downloadUrls = await Promise.all(
        files.map(async (f) => {
          const ext = path.extname(f.originalname);
          const base = path
            .basename(f.originalname, ext)
            .replace(/[^a-zA-Z0-9-_]/g, '_')
            .substring(0, 80);
          const fileName = `${base}_${Date.now()}_${Math.floor(Math.random() * 1_000_000)}${ext}`;
          const contentType =
            f.mimetype && f.mimetype.startsWith('image/') ? f.mimetype : 'application/octet-stream';
          const { publicUrl } = await uploadToSupabaseStorage({
            subKey: `made-to-order/${sanitizedRef}/references/${fileName}`,
            buffer: f.buffer,
            contentType,
          });
          return publicUrl;
        }),
      );
    } else if (isCloudinaryUploadsEnabled()) {
      downloadUrls = await Promise.all(
        files.map(async (f) => {
          const ext = path.extname(f.originalname);
          const base = path
            .basename(f.originalname, ext)
            .replace(/[^a-zA-Z0-9-_]/g, '_')
            .substring(0, 80);
          const fileName = `${base}_${Date.now()}_${Math.floor(Math.random() * 1_000_000)}${ext}`;
          const { secureUrl } = await uploadImageBuffer({
            subFolder: `made-to-order/${sanitizedRef}/references`,
            fileName,
            buffer: f.buffer,
          });
          return secureUrl;
        }),
      );
    } else {
      downloadUrls = files.map((f) => {
        const relative = path.relative(madeToOrderDir, f.path);
        return `/uploads/made-to-order/${relative.replace(/\\/g, '/')}`;
      });
    }
    try {
      await ensureMadeToOrderRequestsTable();
      const pool = getPool();
      await pool.query(
        `UPDATE made_to_order_requests
         SET reference_urls_json = CAST(? AS JSON), updated_at = NOW()
         WHERE request_ref = ?`,
        [JSON.stringify(downloadUrls), requestRef],
      );
    } catch (e) {
      console.warn('Failed to persist made-to-order reference URLs:', e);
    }
    return res.json({
      success: true,
      data: { downloadUrls, requestRef },
    });
  }),
);

orderRouter.post(
  '/:id/paymongo-checkout',
  asyncHandler(async (req, res) => {
    const orderId = req.params.id;
    const userId = req.body.userId as string | undefined;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }

    const order = await getOrderById(orderId);
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }
    if (order.userId !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }

    const pm = order.shippingAddress['paymentMethod'];
    if (pm !== 'paymongo') {
      return res.status(400).json({ success: false, message: 'Order is not PayMongo' });
    }

    const orderStatus = order.status.toLowerCase();
    if (orderStatus === 'cancelled') {
      return res.status(400).json({
        success: false,
        message: 'Order not awaiting payment',
      });
    }

    const total = order.totalAmount;
    const pool = getPool();
    const [payRows] = await pool.query<RowDataPacket[]>(
      `SELECT payment_plan AS paymentPlan, payment_status AS paymentStatus,
              downpayment_amount AS downpaymentAmount, remaining_balance AS remainingBalance,
              payment_proof_url AS paymentProofUrl,
              first_installment_paid_at AS firstInstallmentPaidAt
       FROM orders WHERE id = ? LIMIT 1`,
      [orderId],
    );
    const pr = payRows[0] as
      | {
          paymentPlan: string | null;
          paymentStatus: string;
          downpaymentAmount: number | null;
          remainingBalance: number | null;
          paymentProofUrl: string | null;
          firstInstallmentPaidAt: Date | string | null;
        }
      | undefined;

    const plan = pr?.paymentPlan ?? (order.shippingAddress['paymentPlan'] as string | undefined);
    const psRaw = pr?.paymentStatus ?? 'pending';
    const ps = psRaw.toString().toLowerCase();
    const rem = Number(pr?.remainingBalance ?? order.shippingAddress['remainingBalance'] ?? 0);
    const dp = Number(pr?.downpaymentAmount ?? order.shippingAddress['downpayment'] ?? 0);

    // -------------------------------------------------------------------------
    // First PayMongo tranche vs "pay again" (installment / balance) detection
    // -------------------------------------------------------------------------
    // We used to key only on `payment_status === 'pending'`. If the first GCash
    // payment succeeded but webhooks/ENUM left `payment_status` stuck on `pending`,
    // the route still forced the original DP amount → 400 when the user paid any
    // other amount toward `remaining_balance`. Treat a stored webhook id
    // (`payment_proof_url`) or `first_installment_paid_at` as proof the first
    // tranche already landed so follow-up amounts are allowed.
    // -------------------------------------------------------------------------
    const proofTrimmed = (pr?.paymentProofUrl ?? '').toString().trim();
    const hasFirstInstallmentAnchor =
      pr?.firstInstallmentPaidAt != null && String(pr?.firstInstallmentPaidAt).length > 0;
    const hasPaymongoWebhookId = proofTrimmed.length > 0;
    const paidOrPastFirstTranche =
      ps === 'downpayment_received' ||
      ps === 'completed' ||
      hasFirstInstallmentAnchor ||
      hasPaymongoWebhookId;

    const expectLockedDownPaymentOnly =
      plan === 'downpayment' && ps === 'pending' && !paidOrPastFirstTranche;

    const amountRaw = req.body.amountPesos;
    let requestedAmountPesos: number | undefined;
    if (amountRaw !== undefined && amountRaw !== null && amountRaw !== '') {
      const n =
        typeof amountRaw === 'number' ? amountRaw : Number(String(amountRaw).replace(/,/g, ''));
      requestedAmountPesos = Number.isFinite(n) ? n : undefined;
    }

    // Allow follow-up payments for down-payment plans as long as there's a remaining balance,
    // even if the admin already moved `order.status` to `confirmed`.
    const isDownPlan = plan === 'downpayment';
    const isPaymongoBalanceFollowUp = isDownPlan && rem > 0.01 && orderStatus !== 'cancelled';
    const isAllowedOrderState =
      orderStatus === 'pending' ||
      orderStatus === 'pending_payment_verification' ||
      isPaymongoBalanceFollowUp;

    if (!isAllowedOrderState) {
      return res.status(400).json({
        success: false,
        message: 'Order not awaiting payment',
      });
    }

    /** Full payment vs down-payment first charge vs balance settlement (later PayMongo sessions). */
    let chargePesos: number;
    if (expectLockedDownPaymentOnly) {
      // First tranche (down payment) must remain fixed at DP.
      if (requestedAmountPesos != null) {
        // Enforce a strict match to avoid messing up the 3-month policy window.
        if (Math.abs(requestedAmountPesos - dp) > 0.01) {
          return res.status(400).json({
            success: false,
            message: 'Down payment amount must be exactly the required DP amount.',
          });
        }
      }
      chargePesos = dp;
    } else if (plan === 'downpayment' && rem > 0.01) {
      // Pay-again stage: custom partial payments (requires past first tranche or webhook evidence above).
      if (requestedAmountPesos != null) {
        if (!Number.isFinite(requestedAmountPesos) || requestedAmountPesos <= 0.01) {
          return res.status(400).json({
            success: false,
            message: 'Invalid amountPesos. Must be greater than ₱0.01.',
          });
        }
        if (requestedAmountPesos - rem > 0.01) {
          return res.status(400).json({
            success: false,
            message: `Requested amount exceeds remaining balance.`,
          });
        }
        chargePesos = requestedAmountPesos;
      } else {
        chargePesos = rem;
      }
    } else if (plan === 'downpayment') {
      return res.status(400).json({
        success: false,
        message: 'No remaining balance for this order.',
      });
    } else {
      // Full one-shot payments must remain fixed.
      if (requestedAmountPesos != null && Math.abs(requestedAmountPesos - total) > 0.01) {
        return res.status(400).json({
          success: false,
          message: 'Amount is fixed for this payment stage.',
        });
      }
      chargePesos = total;
    }

    const appendParamsToUrl = (baseUrl: string, params: Record<string, string>): string => {
      const url = new URL(baseUrl);
      for (const [k, v] of Object.entries(params)) {
        url.searchParams.set(k, v);
      }
      return url.toString();
    };

    const successUrl = appendParamsToUrl(config.paymongo.successUrl, {
      orderId: order.id,
      amountPesos: chargePesos.toString(),
    });
    const cancelUrl = appendParamsToUrl(config.paymongo.cancelUrl, {
      orderId: order.id,
    });

    try {
      const session = await createPaymongoCheckoutSession({
        orderId: order.id,
        amountPesos: chargePesos,
        // Keep checkout text neutral (no app name branding).
        description: `Order payment ${order.id}`,
        successUrl,
        cancelUrl,
      });
      res.json({
        success: true,
        data: {
          checkoutUrl: session.checkoutUrl,
          checkoutSessionId: session.checkoutSessionId,
        },
      });
    } catch (e) {
      const message = e instanceof Error ? e.message : 'PayMongo failed';
      console.error('paymongo-checkout:', e);
      res.status(503).json({ success: false, message });
    }
  }),
);

/**
 * POST /api/orders/:id/valid-id
 * multipart: file (image), field userId
 */
orderRouter.post(
  '/:id/valid-id',
  validIdUpload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No file uploaded' });
    }
    const orderId = req.params.id;
    const userId = req.body.userId as string | undefined;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    const order = await getOrderById(orderId);
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }
    if (order.userId !== userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }
    let downloadUrl: string;
    const sanitized = orderId.replace(/[^a-z0-9-_]/gi, '-');
    const ext = path.extname(req.file.originalname);
    const fileName = `valid_id_${orderId.substring(0, 8)}_${Date.now()}${ext}`;
    if (isSupabaseStorageEnabled()) {
      const contentType =
        req.file.mimetype && req.file.mimetype.startsWith('image/')
          ? req.file.mimetype
          : 'application/octet-stream';
      const { publicUrl } = await uploadToSupabaseStorage({
        subKey: `valid-ids/${sanitized}/${fileName}`,
        buffer: req.file.buffer,
        contentType,
      });
      downloadUrl = publicUrl;
    } else if (isCloudinaryUploadsEnabled()) {
      const { secureUrl } = await uploadImageBuffer({
        subFolder: `valid-ids/${sanitized}`,
        fileName,
        buffer: req.file.buffer,
      });
      downloadUrl = secureUrl;
    } else {
      const relative = path.relative(validIdsDir, req.file.path);
      downloadUrl = `/uploads/valid-ids/${relative.replace(/\\/g, '/')}`;
    }
    await updateOrderValidIdProofUrl(orderId, downloadUrl);
    res.json({
      success: true,
      data: { downloadUrl, orderId },
    });
  }),
);

orderRouter.patch(
  '/:id/status',
  asyncHandler(async (req, res) => {
    const payload = statusSchema.parse(req.body);
    await updateOrderStatus(req.params.id, payload.status);
    const adminId = req.body.adminId != null ? String(req.body.adminId).trim() : '';
    if (adminId.length > 0) {
      const normalizedStatus = payload.status.toLowerCase();
      const action =
        normalizedStatus === 'cancelled'
          ? 'order_cancelled'
          : normalizedStatus === 'confirmed'
              ? 'order_confirmed'
              : normalizedStatus === 'shipped'
                  ? 'order_shipped'
                  : normalizedStatus === 'delivered'
                      ? 'order_delivered'
                      : 'order_status_updated';
      await logAdminActivity({
        adminId,
        action,
        entityType: 'order',
        entityId: req.params.id,
        details: { status: payload.status },
      });
    }
    res.status(204).send();
  }),
);

/**
 * POST /api/orders/:id/confirm-payment
 * Admin endpoint to confirm payment proof and update order status
 * 
 * Body:
 * {
 *   adminId: string
 * }
 */
orderRouter.post(
  '/:id/confirm-payment',
  asyncHandler(async (req, res) => {
    const orderId = req.params.id;
    const adminId = req.body.adminId as string;
    
    if (!adminId) {
      return res.status(400).json({
        success: false,
        message: 'adminId is required',
      });
    }
    
    await confirmPayment(orderId, adminId);
    await logAdminActivity({
      adminId,
      action: 'order_payment_confirmed',
      entityType: 'order',
      entityId: orderId,
    });
    res.json({
      success: true,
      message: 'Payment confirmed successfully',
    });
  }),
);

