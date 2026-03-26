import path from 'path';
import fs from 'fs';
import multer from 'multer';
import { Router } from 'express';
import { RowDataPacket } from 'mysql2';
import { z } from 'zod';
import { getPool } from '../config/database';
import { asyncHandler } from '../utils/async_handler';
import { madeToOrderDir, validIdsDir } from '../utils/uploads';
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
  storage: validIdStorage,
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
  storage: mtoStorage,
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
    const relative = path.relative(madeToOrderDir, req.file.path);
    const downloadUrl = `/uploads/made-to-order/${relative.replace(/\\/g, '/')}`;
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
    const downloadUrls = files.map((f) => {
      const relative = path.relative(madeToOrderDir, f.path);
      return `/uploads/made-to-order/${relative.replace(/\\/g, '/')}`;
    });
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

    const requestedAmountPesos = req.body.amountPesos as number | undefined;

    const pm = order.shippingAddress['paymentMethod'];
    if (pm !== 'paymongo') {
      return res.status(400).json({ success: false, message: 'Order is not PayMongo' });
    }

    if (order.status !== 'pending' && order.status !== 'pending_payment_verification') {
      return res.status(400).json({
        success: false,
        message: 'Order not awaiting payment',
      });
    }

    const total = order.totalAmount;
    const pool = getPool();
    const [payRows] = await pool.query<RowDataPacket[]>(
      `SELECT payment_plan AS paymentPlan, payment_status AS paymentStatus,
              downpayment_amount AS downpaymentAmount, remaining_balance AS remainingBalance
       FROM orders WHERE id = ? LIMIT 1`,
      [orderId],
    );
    const pr = payRows[0] as
      | {
          paymentPlan: string | null;
          paymentStatus: string;
          downpaymentAmount: number | null;
          remainingBalance: number | null;
        }
      | undefined;

    const plan = pr?.paymentPlan ?? (order.shippingAddress['paymentPlan'] as string | undefined);
    const ps = pr?.paymentStatus ?? 'pending';
    const rem = Number(pr?.remainingBalance ?? order.shippingAddress['remainingBalance'] ?? 0);
    const dp = Number(pr?.downpaymentAmount ?? order.shippingAddress['downpayment'] ?? 0);

    /** Full payment vs down-payment first charge vs balance settlement (second PayMongo session). */
    let chargePesos: number;
    if (plan === 'downpayment' && ps === 'pending') {
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
    } else if (plan === 'downpayment' && ps === 'downpayment_received') {
      // Pay-again stage: allow user-chosen amount (partial payments allowed).
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

    const appendOrderIdToUrl = (baseUrl: string, id: string): string => {
      const hasQuery = baseUrl.includes('?');
      return hasQuery
        ? `${baseUrl}&orderId=${encodeURIComponent(id)}`
        : `${baseUrl}?orderId=${encodeURIComponent(id)}`;
    };

    const successUrl = appendOrderIdToUrl(config.paymongo.successUrl, order.id);
    const cancelUrl = appendOrderIdToUrl(config.paymongo.cancelUrl, order.id);

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
    const relative = path.relative(validIdsDir, req.file.path);
    const downloadUrl = `/uploads/valid-ids/${relative.replace(/\\/g, '/')}`;
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
    res.json({
      success: true,
      message: 'Payment confirmed successfully',
    });
  }),
);

