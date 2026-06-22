import { RowDataPacket, ResultSetHeader } from 'mysql2';
import type { Connection, Pool } from 'mysql2/promise';
import { getPool } from '../config/database';
import { OrderRecord } from '../models/order_record';
import { parseJsonRecord, parseStringArray } from '../utils/parser';
import { EmailService } from './email_service';
import { ensureInvoiceTables } from './order_invoice_service';
import { createNotificationForUser } from './user_notification_service';
import {
  deductMaterialsForOrder,
  restoreMaterialsForOrder,
  shouldRestoreMaterials,
  validateMaterialStockForOrder,
} from './material_inventory_service';
import { ensureProductVariantSchema } from './product_variant_service';

type OrderRow = RowDataPacket & {
  readonly id: string;
  readonly user_id: string;
  readonly user_name: string | null;
  /**
   * Snapshot: Terms version accepted at order creation time.
   * Optional for backwards compatibility (older DBs won't have the column).
   */
  readonly terms_version_accepted_at_order?: number | null;
  readonly contact_name: string;
  readonly contact_phone: string;
  readonly shipping_label: string | null;
  readonly shipping_line1: string;
  readonly shipping_line2: string | null;
  readonly shipping_region: string;
  readonly shipping_postal: string | null;
  readonly subtotal_amount: number;
  readonly shipping_fee: number;
  readonly total_amount: number;
  readonly downpayment_amount: number | null;
  readonly remaining_balance: number | null;
  /** Planned first tranche for down-payment checkout (0 until paid). */
  readonly planned_downpayment_amount?: number | null;
  readonly status: string;
  readonly payment_method: string;
  /** full | downpayment — nullable if migration not applied */
  readonly payment_plan?: string | null;
  /** layaway | hulugan — down-payment checkout path */
  readonly order_option?: string | null;
  readonly payment_status: string;
  readonly payment_proof_url: string | null;
  /** Last processed PayMongo webhook event id for explicit idempotency. */
  readonly last_paymongo_event_id?: string | null;
  readonly valid_id_proof_url?: string | null;
  readonly cancellation_reason?: string | null;
  readonly payment_default_cancelled_at?: Date | string | null;
  readonly payment_default_warn_2m_sent_at?: Date | string | null;
  readonly payment_default_warn_80d_sent_at?: Date | string | null;
  readonly payment_default_warn_90d_sent_at?: Date | string | null;
  /** Set when first PayMongo tranche (down payment) posts — 3-month policy window starts here */
  readonly first_installment_paid_at?: Date | string | null;
  readonly estimated_delivery_at?: Date | string | null;
  readonly actual_delivery_at?: Date | string | null;
  readonly created_at: Date;
  readonly updated_at: Date;
};

const mapOrder = async (row: OrderRow): Promise<OrderRecord> => {
  const createdAt = row.created_at instanceof Date 
    ? row.created_at 
    : row.created_at 
      ? new Date(row.created_at) 
      : new Date();
  const updatedAt = row.updated_at instanceof Date 
    ? row.updated_at 
    : row.updated_at 
      ? new Date(row.updated_at) 
      : createdAt;
  
  // Fetch product IDs from order_items table
  const pool = getPool();
  const [itemRows] = await pool.query<RowDataPacket[]>(
    'SELECT product_id FROM order_items WHERE order_id = ?',
    [row.id],
  );
  const productIds = itemRows.map((item) => item.product_id as string);
  
  // Reconstruct shipping address from individual fields
  // Include downpayment and remaining balance for GCash orders
  const rawFirst = row.first_installment_paid_at;
  const firstInstallmentIso =
    rawFirst != null
      ? rawFirst instanceof Date
        ? rawFirst.toISOString()
        : new Date(rawFirst as string).toISOString()
      : undefined;

  const rawEst = row.estimated_delivery_at;
  const estimatedDeliveryIso =
    rawEst != null
      ? rawEst instanceof Date
        ? rawEst.toISOString()
        : new Date(rawEst as string).toISOString()
      : undefined;

  const shippingAddress: Record<string, unknown> = {
    name: row.contact_name,
    phone: row.contact_phone,
    line1: row.shipping_line1,
    line2: row.shipping_line2 ?? '',
    city: row.shipping_region,
    postalCode: row.shipping_postal ?? '',
    label: row.shipping_label ?? 'Home',
    downpayment: row.downpayment_amount ?? 0,
    remainingBalance: row.remaining_balance ?? row.total_amount,
    plannedDownPayment: Number(row.planned_downpayment_amount ?? 0) || undefined,
    validIdUrl: row.valid_id_proof_url ?? undefined,
    // So Flutter can show correct payment UI (GCash manual vs PayMongo vs COD)
    paymentMethod: row.payment_method,
    paymentPlan: row.payment_plan ?? undefined,
    orderOption: row.order_option ?? undefined,
    /** Mirrors DB enum — used by Orders tab / Pay flow */
    paymentStatus: row.payment_status,
    /** ISO — start of 3-month 0% window (first PayMongo payment) */
    ...(firstInstallmentIso !== undefined ? { firstInstallmentPaidAt: firstInstallmentIso } : {}),
    ...(estimatedDeliveryIso !== undefined ? { estimatedDeliveryAt: estimatedDeliveryIso } : {}),
    ...(row.actual_delivery_at != null
      ? {
          actualDeliveryAt:
            row.actual_delivery_at instanceof Date
              ? row.actual_delivery_at.toISOString()
              : new Date(row.actual_delivery_at as string).toISOString(),
        }
      : {}),
    /** Set when an order is automatically cancelled due to payment default. */
    cancellationReason: row.cancellation_reason ?? undefined,
    ...(row.payment_default_cancelled_at != null
      ? {
          paymentDefaultCancelledAt:
            row.payment_default_cancelled_at instanceof Date
              ? row.payment_default_cancelled_at.toISOString()
              : new Date(row.payment_default_cancelled_at as string).toISOString(),
        }
      : {}),
  };
  
  return {
    id: row.id,
    userId: row.user_id,
    userName: row.user_name ?? row.contact_name,
    productIds: productIds,
    totalAmount: Number(row.total_amount),
    status: row.status,
    shippingAddress: shippingAddress,
    paymentProofUrl: row.payment_proof_url ?? undefined,
    termsVersionAcceptedAtOrder:
      row.terms_version_accepted_at_order != null
        ? Number(row.terms_version_accepted_at_order)
        : undefined,
    createdAt: createdAt,
    updatedAt: updatedAt,
  };
};

/**
 * Safety net for legacy / stale rows:
 * If fulfillment status says shipped/delivered but money is still owed,
 * force it back to confirmed so fulfillment cannot continue early.
 */
const reconcileFulfillmentStatusForOutstandingBalance = async (
  pool: Pool,
  orderId?: string,
): Promise<void> => {
  if (orderId != null) {
    await pool.query(
      `UPDATE orders
       SET status = 'confirmed',
           updated_at = NOW()
       WHERE id = ?
         AND LOWER(TRIM(COALESCE(status, ''))) IN ('shipped', 'delivered')
         AND COALESCE(remaining_balance, 0) > 0.01`,
      [orderId],
    );
    return;
  }

  await pool.query(
    `UPDATE orders
     SET status = 'confirmed',
         updated_at = NOW()
     WHERE LOWER(TRIM(COALESCE(status, ''))) IN ('shipped', 'delivered')
       AND COALESCE(remaining_balance, 0) > 0.01`,
  );
};

const notifyAdminsOrderFullyPaid = async (params: {
  readonly orderId: string;
  readonly paidAmount: number;
  readonly previousRemaining: number;
}): Promise<void> => {
  if (params.previousRemaining <= 0.01) {
    return;
  }
  await EmailService.sendAdminEventEmail({
    title: 'Order Fully Paid',
    message: `Order #${params.orderId.substring(0, 8).toUpperCase()} has been fully paid.`,
    details: [
      { label: 'Order ID', value: params.orderId },
      { label: 'Payment Received', value: `₱${params.paidAmount.toFixed(2)}` },
      { label: 'Previous Remaining Balance', value: `₱${params.previousRemaining.toFixed(2)}` },
    ],
  });
};

/** Fire-and-forget: new checkout — admins get inbox mail even when offline. */
const notifyAdminsNewOrderPlaced = (params: {
  readonly orderId: string;
  readonly userId: string;
  readonly customerName: string;
  readonly totalAmount: number;
  readonly paymentMethod: string;
  readonly status: string;
}): void => {
  const shortRef = params.orderId.substring(0, 8).toUpperCase();
  EmailService.sendAdminEventEmail({
    title: 'New order placed',
    message: `A customer placed order #${shortRef}. Review it in the admin Orders panel.`,
    details: [
      { label: 'Order ID', value: params.orderId },
      { label: 'User ID', value: params.userId },
      { label: 'Customer', value: params.customerName || 'n/a' },
      { label: 'Total', value: `₱${params.totalAmount.toFixed(2)}` },
      { label: 'Payment method', value: params.paymentMethod },
      { label: 'Status', value: params.status },
    ],
  }).catch((error) => {
    console.error('Failed to send admin new-order alert email:', error);
  });
};

/** Fire-and-forget: user uploaded proof — pending admin verification. */
const notifyAdminsPaymentProofUploaded = (params: {
  readonly orderId: string;
  readonly userId: string;
  readonly totalAmount: number;
  readonly paymentMethod: string;
}): void => {
  const shortRef = params.orderId.substring(0, 8).toUpperCase();
  EmailService.sendAdminEventEmail({
    title: 'Payment proof uploaded',
    message: `Order #${shortRef} has a new payment proof awaiting verification.`,
    details: [
      { label: 'Order ID', value: params.orderId },
      { label: 'User ID', value: params.userId },
      { label: 'Amount', value: `₱${params.totalAmount.toFixed(2)}` },
      { label: 'Payment method', value: params.paymentMethod },
      { label: 'Status', value: 'pending_payment_verification' },
    ],
  }).catch((error) => {
    console.error('Failed to send admin payment-proof alert email:', error);
  });
};

const toShortOrderRef = (orderId: string): string => orderId.substring(0, 8).toUpperCase();

const buildOrderStatusNotification = (
  status: string,
  orderId: string,
): { type: string; title: string; body: string } => {
  const shortRef = toShortOrderRef(orderId);
  switch (status) {
    case 'confirmed':
      return {
        type: 'order_confirmed',
        title: 'Order confirmed',
        body: `Order #${shortRef} has been confirmed and is now being prepared.`,
      };
    case 'shipped':
      return {
        type: 'order_shipped',
        title: 'Order shipped',
        body: `Order #${shortRef} is now on the way.`,
      };
    case 'delivered':
      return {
        type: 'order_delivered',
        title: 'Order delivered',
        body: `Order #${shortRef} has been delivered.`,
      };
    case 'cancelled':
      return {
        type: 'order_cancelled',
        title: 'Order cancelled',
        body: `Order #${shortRef} was cancelled.`,
      };
    case 'pending':
      return {
        type: 'order_pending',
        title: 'Order pending',
        body: `Order #${shortRef} is pending for processing.`,
      };
    default:
      return {
        type: 'order_status_updated',
        title: 'Order status updated',
        body: `Order #${shortRef} status is now ${status}.`,
      };
  }
};

const notifyUserOrderStatusChanged = async (params: {
  readonly userId: string;
  readonly orderId: string;
  readonly previousStatus: string;
  readonly nextStatus: string;
}): Promise<void> => {
  const previous = params.previousStatus.trim().toLowerCase();
  const next = params.nextStatus.trim().toLowerCase();
  if (!next || previous === next) return;

  const notification = buildOrderStatusNotification(next, params.orderId);
  await createNotificationForUser({
    userId: params.userId,
    type: notification.type,
    title: notification.title,
    body: notification.body,
    data: {
      orderId: params.orderId,
      previousStatus: previous,
      status: next,
    },
    push: true,
  });
};

export const listOrders = async (): Promise<OrderRecord[]> => {
  const pool = getPool();
  // Auto-heal rows before returning them to admin/user apps.
  await reconcileFulfillmentStatusForOutstandingBalance(pool);
  const [rows] = await pool.query<OrderRow[]>(
    `
    SELECT o.*, u.full_name AS user_name
    FROM orders o
    LEFT JOIN users u ON o.user_id = u.id
    ORDER BY o.created_at DESC
  `,
  );
  return Promise.all(rows.map(mapOrder));
};

/**
 * Load a single order by id (used for PayMongo checkout verification).
 */
/**
 * Store one valid government ID image URL for an order (KYC / installment policy).
 */
export const updateOrderValidIdProofUrl = async (orderId: string, proofUrl: string): Promise<void> => {
  const pool = getPool();
  try {
    await pool.query(`UPDATE orders SET valid_id_proof_url = ?, updated_at = NOW() WHERE id = ?`, [
      proofUrl,
      orderId,
    ]);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes('valid_id_proof_url') || msg.includes('Unknown column')) {
      throw new Error('Run database migration: app/sql/add_order_plan_id_and_payment_status.sql');
    }
    throw e;
  }
};

export const getOrderById = async (orderId: string): Promise<OrderRecord | null> => {
  const pool = getPool();
  // Keep single-order reads consistent with list reads.
  await reconcileFulfillmentStatusForOutstandingBalance(pool, orderId);
  const [rows] = await pool.query<OrderRow[]>(
    `SELECT o.*, u.full_name AS user_name
     FROM orders o
     LEFT JOIN users u ON o.user_id = u.id
     WHERE o.id = ?
     LIMIT 1`,
    [orderId],
  );
  if (rows.length === 0) {
    return null;
  }
  return mapOrder(rows[0]);
};

// ---------------------------------------------------------------------------
// Delivery window + inventory reservation (Hulugan vs Lay-away business rules)
// ---------------------------------------------------------------------------

/**
 * Normalize `order_option` from DB / payload so comparisons stay consistent.
 * Expected values from checkout: `layaway` | `hulugan` (lowercase).
 */
const normalizeOrderOption = (raw: string | null | undefined): string =>
  String(raw ?? '')
    .trim()
    .toLowerCase();

/**
 * SmartSpace policy: estimated arrival is **10–12 calendar days** after the
 * relevant payment milestone (randomized per assignment so we do not promise a single fixed day).
 */
const randomDeliveryOffsetDays = (): number => 10 + Math.floor(Math.random() * 3);

/** Hulugan unlock threshold — 40% of order total must be approved before confirmation. */
const HULUGAN_CONFIRM_PERCENT = 40;

/** Made-to-order manufacturing buffer after full payment. */
const MTO_DELIVERY_DAYS = 42;

let orderFulfillmentSchemaEnsured = false;

/** Ensures reserved/in_progress statuses and actual_delivery_at exist (idempotent). */
export const ensureOrderFulfillmentSchema = async (pool: Pool): Promise<void> => {
  if (orderFulfillmentSchemaEnsured) return;
  try {
    await pool.query(
      `ALTER TABLE orders
       ADD COLUMN actual_delivery_at DATETIME NULL DEFAULT NULL
       COMMENT 'Recorded when admin marks order delivered'`,
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (!msg.includes('Duplicate column') && !msg.toLowerCase().includes('duplicate column name')) {
      console.warn('ensureOrderFulfillmentSchema actual_delivery_at:', msg);
    }
  }
  try {
    await pool.query(
      `ALTER TABLE orders
       MODIFY COLUMN status ENUM(
         'pending',
         'pending_payment_verification',
         'reserved',
         'in_progress',
         'confirmed',
         'shipped',
         'delivered',
         'cancelled',
         'refunded',
         'expired'
       ) DEFAULT 'pending'`,
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn('ensureOrderFulfillmentSchema status enum:', msg);
  }
  orderFulfillmentSchemaEnsured = true;
};

const totalPaidFromOrder = (orderTotal: number, remainingBalance: number): number =>
  Math.max(0, Number((orderTotal - remainingBalance).toFixed(2)));

const huluganConfirmThreshold = (orderTotal: number): number =>
  Number(((orderTotal * HULUGAN_CONFIRM_PERCENT) / 100).toFixed(2));

const parseOptionalDate = (raw: Date | string | null | undefined): Date | null => {
  if (raw == null) return null;
  const d = raw instanceof Date ? raw : new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d;
};

/** Detect MTO orders via custom line naming from createMadeToOrderOrderFromRequest. */
const isMtoOrder = async (pool: Pool, orderId: string): Promise<boolean> => {
  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT product_name FROM order_items
     WHERE order_id = ?
       AND product_name LIKE 'Made-to-Order [%'
     LIMIT 1`,
    [orderId],
  );
  return rows.length > 0;
};

const logAdminPaymentEvent = async (
  pool: Pool,
  orderId: string,
  amount: number,
  adminId: string,
): Promise<void> => {
  try {
    await ensureInvoiceTables();
    const safePrefix = orderId.substring(0, 8);
    const safeSuffix = adminId.replace(/[^a-zA-Z0-9]/g, '').slice(0, 16);
    const eventId = `pe_admin_${safePrefix}_${safeSuffix}_${Date.now()}`;
    await pool.query(
      `INSERT INTO order_payment_events (id, order_id, event_type, amount, paymongo_event_id)
       VALUES (?, ?, 'admin_confirmed', ?, NULL)`,
      [eventId, orderId, amount],
    );
  } catch (e) {
    console.warn('logAdminPaymentEvent skipped:', e);
  }
};

export type EvaluateFulfillmentOptions = {
  readonly estimatedDeliveryAt?: string | Date | null;
};

/**
 * Applies confirmed status, ETA, material deduction, and confirmation email.
 * Shared by payment approval evaluator and manual admin confirm.
 */
const applyOrderConfirmed = async (
  pool: Pool,
  orderId: string,
  row: OrderRow,
  options?: EvaluateFulfillmentOptions,
): Promise<void> => {
  const previousStatus = row.status;
  if (previousStatus === 'confirmed' || previousStatus === 'shipped' || previousStatus === 'delivered') {
    return;
  }

  const userId = row.user_id;
  const orderTotal = Number(row.total_amount);
  const isMto = await isMtoOrder(pool, orderId);
  const adminEta = parseOptionalDate(options?.estimatedDeliveryAt ?? null);

  await validateMaterialStockForOrder(pool, orderId);

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    if (adminEta != null) {
      await conn.query(
        `UPDATE orders
         SET status = 'confirmed',
             estimated_delivery_at = ?,
             updated_at = NOW()
         WHERE id = ?`,
        [adminEta, orderId],
      );
    } else if (isMto) {
      await conn.query(
        `UPDATE orders
         SET status = 'confirmed',
             estimated_delivery_at = COALESCE(estimated_delivery_at, DATE_ADD(NOW(), INTERVAL ? DAY)),
             updated_at = NOW()
         WHERE id = ?`,
        [MTO_DELIVERY_DAYS, orderId],
      );
    } else {
      const days = randomDeliveryOffsetDays();
      await conn.query(
        `UPDATE orders
         SET status = 'confirmed',
             estimated_delivery_at = COALESCE(estimated_delivery_at, DATE_ADD(NOW(), INTERVAL ? DAY)),
             updated_at = NOW()
         WHERE id = ?`,
        [days, orderId],
      );
    }

    await deductMaterialsForOrder(conn, orderId);
    await conn.commit();
  } catch (txnErr) {
    await conn.rollback();
    throw txnErr;
  } finally {
    conn.release();
  }

  EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
    console.error('Failed to send confirmation email:', error);
  });
};

/**
 * After admin/PayMongo payment approval, evaluate plan rules and set order status + ETA.
 */
export const evaluateOrderAfterPaymentApproval = async (
  orderId: string,
  options?: EvaluateFulfillmentOptions,
): Promise<{ status: string; confirmed: boolean }> => {
  const pool = getPool();
  await ensureOrderFulfillmentSchema(pool);

  const [orderRows] = await pool.query<OrderRow[]>(
    'SELECT * FROM orders WHERE id = ? LIMIT 1',
    [orderId],
  );
  if (orderRows.length === 0) {
    throw new Error('Order not found');
  }

  const row = orderRows[0];
  const previousStatus = row.status;
  const terminal = new Set(['confirmed', 'shipped', 'delivered', 'cancelled']);
  if (terminal.has(previousStatus)) {
    return { status: previousStatus, confirmed: previousStatus === 'confirmed' };
  }

  const orderTotal = Number(row.total_amount);
  const remaining = Number(row.remaining_balance ?? orderTotal);
  const totalPaid = totalPaidFromOrder(orderTotal, remaining);
  const paymentPlan = (row.payment_plan ?? 'full').toString().toLowerCase();
  const normalizedOption = normalizeOrderOption(row.order_option);
  const isHulugan = normalizedOption === 'hulugan';
  const isLayaway = normalizedOption === 'layaway';
  const isMto = await isMtoOrder(pool, orderId);

  let targetStatus = previousStatus;
  let shouldConfirm = false;

  if (paymentPlan === 'full') {
    if (totalPaid >= orderTotal - 0.01) {
      shouldConfirm = true;
      targetStatus = 'confirmed';
    } else {
      targetStatus = 'pending';
    }
  } else if (isHulugan) {
    const threshold = huluganConfirmThreshold(orderTotal);
    if (totalPaid >= threshold - 0.01) {
      shouldConfirm = true;
      targetStatus = 'confirmed';
    } else if (totalPaid > 0.01) {
      targetStatus = 'pending';
    } else {
      targetStatus = 'pending';
    }
  } else if (isLayaway || isMto) {
    if (totalPaid >= orderTotal - 0.01) {
      shouldConfirm = true;
      targetStatus = 'confirmed';
    } else if (totalPaid > 0.01) {
      targetStatus = isMto ? 'in_progress' : 'reserved';
    } else {
      targetStatus = 'pending';
    }
  } else if (paymentPlan === 'downpayment') {
    if (totalPaid >= orderTotal - 0.01) {
      shouldConfirm = true;
      targetStatus = 'confirmed';
    } else if (totalPaid > 0.01) {
      targetStatus = 'reserved';
    } else {
      targetStatus = 'pending';
    }
  }

  if (shouldConfirm) {
    await applyOrderConfirmed(pool, orderId, row, options);
    notifyUserOrderStatusChanged({
      userId: row.user_id,
      orderId,
      previousStatus,
      nextStatus: 'confirmed',
    }).catch((error) => {
      console.error('Failed to send order status push notification:', error);
    });
    return { status: 'confirmed', confirmed: true };
  }

  await pool.query('UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?', [
    targetStatus,
    orderId,
  ]);

  if (previousStatus !== targetStatus) {
    notifyUserOrderStatusChanged({
      userId: row.user_id,
      orderId,
      previousStatus,
      nextStatus: targetStatus,
    }).catch((error) => {
      console.error('Failed to send order status push notification:', error);
    });
  }

  return { status: targetStatus, confirmed: false };
};

const isMissingEstimatedDeliveryColumn = (msg: string): boolean =>
  msg.includes('estimated_delivery_at') || msg.includes('order_option') || msg.includes('Unknown column');

/**
 * **Hulugan**: first PayMongo tranche (down payment requirement met) → start the delivery window
 * from `first_installment_paid_at` (same instant as DP), even if balance remains.
 */
const trySetHuluganEstimatedDeliveryAfterDownPayment = async (
  pool: Pool,
  orderId: string,
): Promise<void> => {
  const days = randomDeliveryOffsetDays();
  try {
    await pool.query(
      `UPDATE orders
       SET estimated_delivery_at = DATE_ADD(COALESCE(first_installment_paid_at, NOW()), INTERVAL ? DAY),
           updated_at = NOW()
       WHERE id = ?
         AND LOWER(TRIM(COALESCE(order_option, ''))) = 'hulugan'`,
      [days, orderId],
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (isMissingEstimatedDeliveryColumn(msg)) {
      return;
    }
    throw e;
  }
};

/**
 * **Lay-away** (and full one-shot PayMongo): delivery window starts only after **full settlement**
 * (`payment_status` transition to completed in caller). **Hulugan** second tranche must **not**
 * move the ETA (already anchored at DP). One-shot full pay on a hulugan order still uses this path
 * when `estimated_delivery_at` is still null.
 */
const trySetEstimatedDeliveryAfterFullPaymentIfNeeded = async (
  pool: Pool,
  orderId: string,
): Promise<void> => {
  const days = randomDeliveryOffsetDays();
  try {
    await pool.query(
      `UPDATE orders
       SET estimated_delivery_at = DATE_ADD(NOW(), INTERVAL ? DAY),
           updated_at = NOW()
       WHERE id = ?
         AND (
           estimated_delivery_at IS NULL
           OR LOWER(TRIM(COALESCE(order_option, ''))) <> 'hulugan'
         )`,
      [days, orderId],
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (isMissingEstimatedDeliveryColumn(msg)) {
      return;
    }
    throw e;
  }
};

/**
 * When an order is abandoned (expired) or cancelled, put physical qty back on the shelf.
 * Idempotent with respect to **double release**: only release when entering terminal state
 * from a non-terminal state (e.g. expired → cancelled must not add stock twice).
 */
const shouldReleaseReservedInventory = (previousStatus: string, nextStatus: string): boolean => {
  if (nextStatus !== 'cancelled' && nextStatus !== 'expired') {
    return false;
  }
  if (previousStatus === 'cancelled' || previousStatus === 'expired') {
    return false;
  }
  return true;
};

/**
 * Decrement `products.inventory_qty` for every `order_items` row (supports qty & duplicate SKUs).
 * Caller must run inside a transaction so the order row + items roll back if any line fails.
 */
const decrementInventoryForOrder = async (conn: Connection, orderId: string): Promise<void> => {
  const [items] = await conn.query<RowDataPacket[]>(
    'SELECT product_id, quantity FROM order_items WHERE order_id = ?',
    [orderId],
  );
  for (const item of items) {
    const productId = item.product_id as string;
    const qty = Number(item.quantity);
    if (!Number.isFinite(qty) || qty <= 0) {
      continue;
    }
    // Custom MTO lines reference the request id — not a catalog SKU.
    const [catalog] = await conn.query<RowDataPacket[]>(
      'SELECT id FROM products WHERE id = ? LIMIT 1',
      [productId],
    );
    if (catalog.length === 0) {
      continue;
    }
    const [res] = await conn.query<ResultSetHeader>(
      'UPDATE products SET inventory_qty = inventory_qty - ? WHERE id = ? AND inventory_qty >= ?',
      [qty, productId, qty],
    );
    if (res.affectedRows !== 1) {
      throw new Error(`Insufficient inventory for product ${productId} (need ${qty} unit(s))`);
    }
    await conn.query(
      'UPDATE products SET in_stock = IF(inventory_qty > 0, TRUE, FALSE) WHERE id = ?',
      [productId],
    );
  }
};

/**
 * Reverse {@link decrementInventoryForOrder} — used on cancel / auto-expire.
 */
const restoreInventoryForOrder = async (executor: Pool | Connection, orderId: string): Promise<void> => {
  const [items] = await executor.query<RowDataPacket[]>(
    'SELECT product_id, quantity FROM order_items WHERE order_id = ?',
    [orderId],
  );
  for (const item of items) {
    const productId = item.product_id as string;
    const qty = Number(item.quantity);
    if (!Number.isFinite(qty) || qty <= 0) {
      continue;
    }
    const [catalog] = await executor.query<RowDataPacket[]>(
      'SELECT id FROM products WHERE id = ? LIMIT 1',
      [productId],
    );
    if (catalog.length === 0) {
      continue;
    }
    await executor.query(
      'UPDATE products SET inventory_qty = inventory_qty + ? WHERE id = ?',
      [qty, productId],
    );
    await executor.query(
      'UPDATE products SET in_stock = IF(inventory_qty > 0, TRUE, FALSE) WHERE id = ?',
      [productId],
    );
  }
};

const resolveDefaultVariantId = async (
  conn: Connection,
  productId: string,
): Promise<string | null> => {
  await ensureProductVariantSchema();
  const [rows] = await conn.query<RowDataPacket[]>(
    `SELECT id FROM product_variants WHERE product_id = ? AND is_default = 1 LIMIT 1`,
    [productId],
  );
  return (rows?.[0]?.id as string | undefined) ?? null;
};

const insertOrderItem = async (
  conn: Connection,
  params: {
    orderId: string;
    productId: string;
    variantId: string | null;
    productName: string;
    quantity: number;
    unitPrice: number;
    lineTotal: number;
  },
): Promise<void> => {
  const { generateId: generateItemId } = await import('../utils/id_generator');
  const itemId = generateItemId('oi');
  await ensureProductVariantSchema();
  await conn.query(
    `INSERT INTO order_items (id, order_id, product_id, variant_id, product_name, quantity, unit_price, line_total)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      itemId,
      params.orderId,
      params.productId,
      params.variantId,
      params.productName,
      params.quantity,
      params.unitPrice,
      params.lineTotal,
    ],
  );
};

const approxEqualPesos = (a: number, b: number): boolean => Math.abs(a - b) < 1.0;

/**
 * Ensures the orders table has a dedicated idempotency column for PayMongo webhooks.
 * This keeps duplicate-event protection independent from invoice tables.
 */
const ensureLastPaymongoEventIdColumn = async (pool: Pool): Promise<boolean> => {
  try {
    await pool.query(
      `ALTER TABLE orders
       ADD COLUMN last_paymongo_event_id VARCHAR(191) NULL DEFAULT NULL
       COMMENT 'Last processed PayMongo webhook event id' AFTER payment_proof_url`,
    );
    return true;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes('Duplicate column') || msg.toLowerCase().includes('duplicate column name')) {
      return true;
    }
    console.warn('ensureLastPaymongoEventIdColumn:', msg);
    return false;
  }
};

/**
 * First PayMongo tranche succeeded: mark down payment received and anchor `first_installment_paid_at`
 * (3-month policy window). Tolerates missing ENUM value or missing migration column.
 */
const trySetDownpaymentReceived = async (pool: Pool, orderId: string): Promise<void> => {
  const withAnchor = `UPDATE orders SET
    payment_status = 'downpayment_received',
    first_installment_paid_at = COALESCE(first_installment_paid_at, NOW()),
    updated_at = NOW()
  WHERE id = ?`;
  const withoutAnchor = `UPDATE orders SET
    payment_status = 'downpayment_received',
    updated_at = NOW()
  WHERE id = ?`;
  const fallbackPending = `UPDATE orders SET
    payment_status = 'pending',
    updated_at = NOW()
  WHERE id = ?`;

  try {
    await pool.query(withAnchor, [orderId]);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('first_installment_paid_at') || msg.includes('Unknown column')) {
      try {
        await pool.query(withoutAnchor, [orderId]);
      } catch (err2) {
        const msg2 = err2 instanceof Error ? err2.message : String(err2);
        if (msg2.includes('downpayment_received') || msg2.includes('Data truncated')) {
          await pool.query(fallbackPending, [orderId]);
        } else {
          throw err2;
        }
      }
    } else if (msg.includes('downpayment_received') || msg.includes('Data truncated')) {
      await pool.query(fallbackPending, [orderId]);
    } else {
      throw err;
    }
  }
};

/**
 * Mark order paid after PayMongo webhook (full payment or down-payment plan phases).
 *
 * Down-payment plan: first successful charge ≈ `downpayment_amount` → `downpayment_received`;
 * second charge ≈ `remaining_balance` → `completed`. Uses optional webhook amount so we never
 * treat a duplicate first-payment event as a balance settlement.
 */
export const markOrderPaidViaPaymongo = async (
  orderId: string,
  options?: { readonly amountPesos?: number | null; readonly eventId?: string | null },
): Promise<void> => {
  const pool = getPool();
  const [orderRows] = await pool.query<OrderRow[]>(
    'SELECT * FROM orders WHERE id = ? LIMIT 1',
    [orderId],
  );

  if (orderRows.length === 0) {
    throw new Error('Order not found');
  }

  const row = orderRows[0];
  if (row.payment_method !== 'paymongo') {
    console.warn(`markOrderPaidViaPaymongo: order ${orderId} is not paymongo, skipping`);
    return;
  }

  const rem = Number(row.remaining_balance ?? 0);
  if (row.status === 'confirmed' && row.payment_status === 'completed' && rem <= 0.01) {
    console.log(`PayMongo webhook: order ${orderId} already confirmed`);
    return;
  }

  const userId = row.user_id;
  const orderTotal = Number(row.total_amount);
  const previousStatus = row.status;
  const previousStatusNormalized = String(previousStatus).trim().toLowerCase();
  const dp = Number(row.downpayment_amount ?? 0);

  const runPaymongoFulfillmentEvaluation = async (): Promise<void> => {
    try {
      await evaluateOrderAfterPaymentApproval(orderId);
    } catch (e) {
      console.error(`evaluateOrderAfterPaymentApproval after PayMongo for ${orderId}:`, e);
    }
  };

  const plan = row.payment_plan ?? null;
  const paidAmount = options?.amountPesos ?? null;
  const eventId = options?.eventId ?? null;
  const normalizedEventId = eventId != null ? eventId.trim() : '';
  const isDownPlan = plan === 'downpayment';

  const hasEventId = normalizedEventId.length > 0;
  const hasWebhookIdColumn = hasEventId
    ? await ensureLastPaymongoEventIdColumn(pool)
    : false;

  // Idempotency guard (primary): explicit webhook ID column on orders.
  if (hasEventId && hasWebhookIdColumn && row.last_paymongo_event_id === normalizedEventId) {
    console.log(`PayMongo webhook: duplicate event ${normalizedEventId} for order ${orderId} — ignored`);
    return;
  }

  // Idempotency guard (fallback): invoice event ledger for older DBs.
  if (hasEventId && !hasWebhookIdColumn) {
    try {
      await ensureInvoiceTables();
      const [dupRows] = await pool.query<RowDataPacket[]>(
        `SELECT id FROM order_payment_events
         WHERE order_id = ? AND paymongo_event_id = ?
         LIMIT 1`,
        [orderId, normalizedEventId],
      );
      if (dupRows.length > 0) {
        console.log(`PayMongo webhook: duplicate event ${normalizedEventId} for order ${orderId} — ignored`);
        return;
      }
    } catch (e) {
      // Keep webhook processing resilient when invoice tables are not present.
      console.warn(`PayMongo webhook idempotency check skipped for ${orderId}:`, e);
    }
  }

  const persistWebhookEventId = async (): Promise<void> => {
    if (!hasEventId || !hasWebhookIdColumn) return;
    await pool.query(
      `UPDATE orders
       SET last_paymongo_event_id = ?, updated_at = NOW()
       WHERE id = ?`,
      [normalizedEventId, orderId],
    );
  };

  const looksLikeInstallmentStructure = rem > 0.01 && dp < orderTotal - 0.01;

  /**
   * Single full PayMongo charge (full plan, or order total equals downpayment line).
   */
  const treatAsSingleFullPayment = !isDownPlan || !looksLikeInstallmentStructure;

  if (treatAsSingleFullPayment) {
    await pool.query(
      `UPDATE orders
       SET payment_status = 'completed',
           remaining_balance = 0,
           downpayment_amount = ?,
           updated_at = NOW()
       WHERE id = ?`,
      [orderTotal, orderId],
    );
    await runPaymongoFulfillmentEvaluation();
    await notifyAdminsOrderFullyPaid({
      orderId,
      paidAmount: paidAmount ?? orderTotal,
      previousRemaining: rem,
    });
    await persistWebhookEventId();
    console.log(`✅ PayMongo full payment recorded for order ${orderId}`);

    // Invoice updates only apply to PayMongo downpayment plans.
    if (isDownPlan && paidAmount != null && paidAmount > 0.01) {
      await ensureInvoiceTables();
      const safePrefix = orderId.substring(0, 8);
      const safeSuffix = (eventId ?? Date.now().toString())
        .replace(/[^a-zA-Z0-9]/g, '')
        .slice(0, 16);
      const paymentEventId = `pe_${safePrefix}_${safeSuffix}`;
      const eventType = row.payment_status === 'pending' ? 'downpayment' : 'installment';

      await pool.query(
        `INSERT INTO order_payment_events (id, order_id, event_type, amount, paymongo_event_id)
         VALUES (?, ?, ?, ?, ?)`,
        [paymentEventId, orderId, eventType, paidAmount, eventId],
      );
      await EmailService.sendUpdatedInvoiceEmail({ userId, orderId });
    }

    return;
  }

  // --- Two-phase down payment plan ---
  if (paidAmount != null) {
    if (row.payment_status === 'pending' && approxEqualPesos(paidAmount, dp)) {
      await trySetDownpaymentReceived(pool, orderId);
      await runPaymongoFulfillmentEvaluation();
      await persistWebhookEventId();
      console.log(`✅ PayMongo down payment recorded for order ${orderId} (balance still due)`);

      if (isDownPlan) {
        await ensureInvoiceTables();
        const safePrefix = orderId.substring(0, 8);
        const safeSuffix = (eventId ?? Date.now().toString())
          .replace(/[^a-zA-Z0-9]/g, '')
          .slice(0, 16);
        const paymentEventId = `pe_${safePrefix}_${safeSuffix}`;

        await pool.query(
          `INSERT INTO order_payment_events (id, order_id, event_type, amount, paymongo_event_id)
           VALUES (?, ?, 'downpayment', ?, ?)`,
          [paymentEventId, orderId, paidAmount, eventId],
        );
        await EmailService.sendUpdatedInvoiceEmail({ userId, orderId });
      }
      return;
    }

    /**
     * `payment_status` still `pending` but payment amount clearly targets remaining balance.
     * This handles stale rows where first tranche was already applied, plus larger one-shot
     * payments that include DP and part/all of the balance.
     */
    if (
      row.payment_status === 'pending' &&
      isDownPlan &&
      rem > 0.01 &&
      paidAmount > 0.01 &&
      paidAmount <= rem + 0.01
    ) {
      const persistEventId = async (): Promise<void> => {
        // Event IDs are tracked in `order_payment_events.paymongo_event_id`.
      };

      // Paying essentially all of `remaining_balance` while the row still says `pending`:
      // treat as the final tranche (stale state after an earlier DP).
      if (approxEqualPesos(paidAmount, rem)) {
        await pool.query(
          `UPDATE orders
           SET payment_status = 'completed',
               remaining_balance = 0,
               updated_at = NOW()
           WHERE id = ?`,
          [orderId],
        );
        await persistEventId();
        await runPaymongoFulfillmentEvaluation();
        await notifyAdminsOrderFullyPaid({
          orderId,
          paidAmount,
          previousRemaining: rem,
        });
        await persistWebhookEventId();
        console.log(`✅ PayMongo balance settled for order ${orderId} (pending row matched remaining)`);

        if (isDownPlan) {
          await ensureInvoiceTables();
          const safePrefix = orderId.substring(0, 8);
          const safeSuffix = (eventId ?? Date.now().toString())
            .replace(/[^a-zA-Z0-9]/g, '')
            .slice(0, 16);
          const paymentEventId = `pe_${safePrefix}_${safeSuffix}`;

          await pool.query(
            `INSERT INTO order_payment_events (id, order_id, event_type, amount, paymongo_event_id)
             VALUES (?, ?, 'installment', ?, ?)`,
            [paymentEventId, orderId, paidAmount, eventId],
          );
          await EmailService.sendUpdatedInvoiceEmail({ userId, orderId });
        }

        return;
      }

      // If remaining is already lower than order total, prior payment has been applied and this
      // amount should reduce remaining directly. Otherwise, a pending one-shot that still includes
      // the required DP should only reduce balance by the portion above DP.
      const hasAlreadyPaidSomething = rem < orderTotal - 0.01;
      const towardBalance = hasAlreadyPaidSomething ? paidAmount : Math.max(0, paidAmount - dp);
      const newRemaining = Math.max(0, rem - towardBalance);
      await pool.query(
        `UPDATE orders
         SET payment_status = 'downpayment_received',
             remaining_balance = ?,
             downpayment_amount = ?,
             updated_at = NOW()
         WHERE id = ?`,
        [newRemaining, orderTotal - newRemaining, orderId],
      );
      await runPaymongoFulfillmentEvaluation();
      await persistEventId();
      await persistWebhookEventId();
      console.log(
        `✅ PayMongo pending plan payment for ${orderId}: paid=${paidAmount}, newRemaining=${newRemaining}`,
      );

      if (newRemaining <= 0.01) {
        await pool.query(
          `UPDATE orders
           SET payment_status = 'completed',
               remaining_balance = 0,
               downpayment_amount = ?,
               updated_at = NOW()
           WHERE id = ?`,
          [orderTotal, orderId],
        );
        await runPaymongoFulfillmentEvaluation();
        await notifyAdminsOrderFullyPaid({
          orderId,
          paidAmount,
          previousRemaining: rem,
        });
        await persistWebhookEventId();
        console.log(`✅ PayMongo balance settled for order ${orderId} (pending single-shot overpay)`);
      }

      if (isDownPlan) {
        await ensureInvoiceTables();
        const safePrefix = orderId.substring(0, 8);
        const safeSuffix = (eventId ?? Date.now().toString())
          .replace(/[^a-zA-Z0-9]/g, '')
          .slice(0, 16);
        const paymentEventId = `pe_${safePrefix}_${safeSuffix}`;

        await pool.query(
          `INSERT INTO order_payment_events (id, order_id, event_type, amount, paymongo_event_id)
           VALUES (?, ?, 'installment', ?, ?)`,
          [paymentEventId, orderId, paidAmount, eventId],
        );
        await EmailService.sendUpdatedInvoiceEmail({ userId, orderId });
      }

      return;
    }

    if (row.payment_status === 'downpayment_received' && approxEqualPesos(paidAmount, rem)) {
      await pool.query(
        `UPDATE orders
         SET payment_status = 'completed',
             remaining_balance = 0,
             downpayment_amount = ?,
             updated_at = NOW()
         WHERE id = ?`,
        [orderTotal, orderId],
      );
      await runPaymongoFulfillmentEvaluation();
      await notifyAdminsOrderFullyPaid({
        orderId,
        paidAmount,
        previousRemaining: rem,
      });
      await persistWebhookEventId();
      console.log(`✅ PayMongo balance settled for order ${orderId}`);

      if (isDownPlan) {
        await ensureInvoiceTables();
        const safePrefix = orderId.substring(0, 8);
        const safeSuffix = (eventId ?? Date.now().toString())
          .replace(/[^a-zA-Z0-9]/g, '')
          .slice(0, 16);
        const paymentEventId = `pe_${safePrefix}_${safeSuffix}`;

        await pool.query(
          `INSERT INTO order_payment_events (id, order_id, event_type, amount, paymongo_event_id)
           VALUES (?, ?, 'installment', ?, ?)`,
          [paymentEventId, orderId, paidAmount, eventId],
        );
        await EmailService.sendUpdatedInvoiceEmail({ userId, orderId });
      }

      return;
    }

    // Partial payment for down-payment plan (pay again stage).
    // Example:
    // - remaining_balance was ₱100
    // - user pays ₱30
    // - remaining_balance becomes ₱70
    // - payment_status stays `downpayment_received` until remaining reaches zero.
    if (row.payment_status === 'downpayment_received' && paidAmount > 0.01 && paidAmount <= rem + 0.01) {
      const newRemaining = Math.max(0, rem - paidAmount);
      await pool.query(
        `UPDATE orders
         SET remaining_balance = ?,
             downpayment_amount = ?,
             payment_status = 'downpayment_received',
             updated_at = NOW()
         WHERE id = ?`,
        [newRemaining, orderTotal - newRemaining, orderId],
      );

      if (newRemaining <= 0.01) {
        await pool.query(
          `UPDATE orders
           SET payment_status = 'completed',
               remaining_balance = 0,
               downpayment_amount = ?,
               updated_at = NOW()
           WHERE id = ?`,
          [orderTotal, orderId],
        );
        await runPaymongoFulfillmentEvaluation();
        await notifyAdminsOrderFullyPaid({
          orderId,
          paidAmount,
          previousRemaining: rem,
        });
        await persistWebhookEventId();
        console.log(`✅ PayMongo balance settled for order ${orderId} (rounding during partial)`);
      }

      if (isDownPlan) {
        await ensureInvoiceTables();
        const safePrefix = orderId.substring(0, 8);
        const safeSuffix = (eventId ?? Date.now().toString())
          .replace(/[^a-zA-Z0-9]/g, '')
          .slice(0, 16);
        const paymentEventId = `pe_${safePrefix}_${safeSuffix}`;

        await pool.query(
          `INSERT INTO order_payment_events (id, order_id, event_type, amount, paymongo_event_id)
           VALUES (?, ?, 'installment', ?, ?)`,
          [paymentEventId, orderId, paidAmount, eventId],
        );
        await EmailService.sendUpdatedInvoiceEmail({ userId, orderId });
      }

      await runPaymongoFulfillmentEvaluation();
      return;
    }

    if (row.payment_status === 'downpayment_received' && approxEqualPesos(paidAmount, dp)) {
      console.log(`PayMongo webhook: duplicate first-installment event for ${orderId} — ignored`);
      return;
    }

    if (row.payment_status === 'pending' && approxEqualPesos(paidAmount, orderTotal)) {
      await pool.query(
        `UPDATE orders
         SET payment_status = 'completed',
             remaining_balance = 0,
             downpayment_amount = ?,
             updated_at = NOW()
         WHERE id = ?`,
        [orderTotal, orderId],
      );
      await runPaymongoFulfillmentEvaluation();
      await notifyAdminsOrderFullyPaid({
        orderId,
        paidAmount,
        previousRemaining: rem,
      });
      await persistWebhookEventId();
      console.log(`✅ PayMongo full payment (amount matched total) for order ${orderId}`);
      return;
    }

    console.warn(
      `PayMongo webhook: amount ${paidAmount} did not match expected phase for ${orderId} ` +
        `(status=${row.payment_status}, dp=${dp}, rem=${rem})`,
    );
  }

  // Fallback when webhook payload has no usable amount (older integrations)
  const isFirstInstallment = looksLikeInstallmentStructure;
  if (row.payment_status === 'pending' && isFirstInstallment) {
    await trySetDownpaymentReceived(pool, orderId);
    await runPaymongoFulfillmentEvaluation();
    await persistWebhookEventId();
    console.log(`✅ PayMongo down payment recorded for order ${orderId} (no amount in webhook — fallback)`);
    return;
  }

  if (row.payment_status === 'downpayment_received' && rem > 0.01) {
    console.warn(
      `PayMongo webhook: order ${orderId} awaiting balance payment — need amount in payload to settle safely`,
    );
    return;
  }

  await pool.query(
    `UPDATE orders
     SET payment_status = 'completed',
         remaining_balance = 0,
         downpayment_amount = ?,
         updated_at = NOW()
     WHERE id = ?`,
    [orderTotal, orderId],
  );
  await runPaymongoFulfillmentEvaluation();
  await notifyAdminsOrderFullyPaid({
    orderId,
    paidAmount: paidAmount ?? orderTotal,
    previousRemaining: rem,
  });
  await persistWebhookEventId();
  console.log(`✅ PayMongo full payment recorded for order ${orderId} (fallback tail)`);
};

/**
 * Mark a PayMongo payment attempt as failed so UI/admin can show a clear state.
 *
 * We only apply this to orders that are:
 * - PayMongo based
 * - not cancelled
 * - not already completed
 */
export const markOrderPaymentFailedViaPaymongo = async (orderId: string): Promise<void> => {
  const pool = getPool();
  const [orderRows] = await pool.query<OrderRow[]>(
    'SELECT * FROM orders WHERE id = ? LIMIT 1',
    [orderId],
  );
  if (orderRows.length === 0) {
    throw new Error('Order not found');
  }

  const row = orderRows[0];
  if (row.payment_method !== 'paymongo') {
    console.warn(`markOrderPaymentFailedViaPaymongo: order ${orderId} is not paymongo, skipping`);
    return;
  }
  if (row.status === 'cancelled') {
    return;
  }
  if (row.payment_status === 'completed') {
    // A late "failed" event must not override completed settlement.
    return;
  }

  await pool.query(
    `UPDATE orders
     SET payment_status = 'failed',
         updated_at = NOW()
     WHERE id = ?`,
    [orderId],
  );
  console.log(`⚠️ PayMongo payment failed recorded for order ${orderId}`);
};

export interface CreateOrderInput {
  readonly userId: string;
  readonly userName: string;
  readonly productIds: readonly string[];
  readonly totalAmount: number;
  readonly shippingAddress: Record<string, unknown>;
  readonly status?: string;
  /**
   * Snapshot of the Terms & Conditions version the user had accepted when the
   * order was created.
   *
   * This must be provided by the route layer after verifying the user has
   * accepted the latest terms.
   */
  readonly termsVersionAcceptedAtOrder?: number;
/**
 * When set, inserts these order lines instead of resolving prices from [productIds].
 * Used for made-to-order (custom line totals).
 */
  readonly lineItemsOverride?: ReadonlyArray<{
    readonly productId: string;
    readonly productName: string;
    readonly quantity: number;
    readonly unitPrice: number;
    readonly lineTotal: number;
    readonly variantId?: string;
  }>;
  /** Catalog lines with optional variant (preferred over productIds). */
  readonly orderLines?: ReadonlyArray<{
    readonly productId: string;
    readonly variantId?: string;
    readonly quantity: number;
  }>;
  /** Custom / MTO lines are not tied to catalog SKUs — skip inventory reservation. */
  readonly skipInventoryReservation?: boolean;
}

/** Legacy placeholder id — archived on startup; no new rows should reference it. */
export const MTO_PLACEHOLDER_PRODUCT_ID = 'p_made_to_order_placeholder';

let orderItemsCustomLinesEnsured = false;

/**
 * MTO order lines use the request id as product_id (no catalog SKU).
 * Drop the products FK when present so custom lines can be stored.
 */
const ensureOrderItemsAllowCustomLines = async (pool: Pool): Promise<void> => {
  if (orderItemsCustomLinesEnsured) return;
  try {
    const [fks] = await pool.query<RowDataPacket[]>(
      `SELECT CONSTRAINT_NAME AS constraintName
       FROM information_schema.KEY_COLUMN_USAGE
       WHERE TABLE_SCHEMA = DATABASE()
         AND TABLE_NAME = 'order_items'
         AND REFERENCED_TABLE_NAME = 'products'
         AND COLUMN_NAME = 'product_id'`,
    );
    for (const row of fks) {
      const name = String(row.constraintName ?? '');
      if (name.length === 0) continue;
      await pool.query(`ALTER TABLE order_items DROP FOREIGN KEY \`${name}\``);
    }
  } catch (e) {
    console.warn('ensureOrderItemsAllowCustomLines:', e);
  }
  orderItemsCustomLinesEnsured = true;
};

/** Hide the old placeholder SKU from admin/catalog (kept for historical order_items). */
export const archiveMadeToOrderPlaceholderProduct = async (pool: Pool): Promise<void> => {
  try {
    await pool.query(
      `UPDATE products
       SET is_archived = 1, in_stock = 0, inventory_qty = 0, updated_at = NOW()
       WHERE id = ?`,
      [MTO_PLACEHOLDER_PRODUCT_ID],
    );
  } catch (e) {
    console.warn('archiveMadeToOrderPlaceholderProduct:', e);
  }
};

export interface CreateMadeToOrderOrderInput {
  readonly userId: string;
  readonly userName: string;
  readonly requestId: string;
  readonly requestRef: string;
  readonly itemName: string;
  readonly quotedTotal: number;
  readonly quotedDownpayment: number;
  readonly quotedRemaining: number;
  readonly shippingAddress: Record<string, unknown>;
}

/**
 * Creates a normal PayMongo down-payment order after admin quoted and user confirmed address.
 */
export const createMadeToOrderOrderFromRequest = async (
  input: CreateMadeToOrderOrderInput,
): Promise<OrderRecord> => {
  const pool = getPool();
  await ensureOrderItemsAllowCustomLines(pool);
  const shippingFee = (input.shippingAddress['shippingFee'] as number) ?? 20.0;
  const merchandiseSubtotal = input.quotedTotal - shippingFee;
  if (merchandiseSubtotal < -0.01) {
    throw new Error('Quoted total must cover shipping.');
  }
  const lineName = `Made-to-Order [${input.requestRef}]: ${input.itemName}`;
  const merged: Record<string, unknown> = {
    ...input.shippingAddress,
    paymentMethod: 'paymongo',
    paymentPlan: 'downpayment',
    orderOption: 'layaway',
    downpayment: input.quotedDownpayment,
    remainingBalance: input.quotedRemaining,
    merchandiseSubtotal,
    shippingFee,
  };
  return createOrder({
    userId: input.userId,
    userName: input.userName,
    productIds: [],
    totalAmount: input.quotedTotal,
    shippingAddress: merged,
    skipInventoryReservation: true,
    lineItemsOverride: [
      {
        productId: input.requestId,
        productName: lineName,
        quantity: 1,
        unitPrice: merchandiseSubtotal,
        lineTotal: merchandiseSubtotal,
      },
    ],
  });
};

export const createOrder = async (input: CreateOrderInput): Promise<OrderRecord> => {
  const pool = getPool();
  const { generateId } = await import('../utils/id_generator');
  const id = generateId('o');
  const status = input.status ?? 'pending';
  
  // Extract shipping address fields
  const shippingAddress = input.shippingAddress as Record<string, unknown>;
  const contactName = (shippingAddress['name'] as string) || input.userName || '';
  const contactPhone = (shippingAddress['phone'] as string) || '';
  const shippingLine1 = (shippingAddress['line1'] as string) || '';
  const shippingLine2 = (shippingAddress['line2'] as string) || '';
  const shippingRegion = (shippingAddress['city'] as string) || '';
  const shippingPostal = (shippingAddress['postalCode'] as string) || '';
  const shippingLabel = (shippingAddress['label'] as string) || 'Home';
  
  // Calculate subtotal and shipping fee
  // Shipping fee is calculated on the frontend based on location and product count
  // If shippingFee is provided in the shippingAddress, use it; otherwise fallback to old calculation
  const shippingFee = (shippingAddress['shippingFee'] as number) ?? 20.0;
  /** Line items subtotal only (excludes shipping & installment interest). Sent by app for hulugan. */
  const merchandiseSubtotal =
    (shippingAddress['merchandiseSubtotal'] as number | undefined) ?? input.totalAmount - shippingFee;
  const subtotalAmount = merchandiseSubtotal;

  // Get payment method from shipping address, default to 'cod' for backwards compatibility
  const paymentMethod = (shippingAddress['paymentMethod'] as string) ?? 'cod';
  const paymentPlan = (shippingAddress['paymentPlan'] as string | undefined) ?? undefined;
  const orderOption = (shippingAddress['orderOption'] as string | undefined) ?? undefined;

  // Paid so far (0 at checkout). Planned first tranche stored separately for down-payment plans.
  const downpayment = Number(shippingAddress['downpayment'] ?? 0);
  const remainingBalance =
    Number(shippingAddress['remainingBalance'] ?? input.totalAmount) || input.totalAmount;
  const plannedDownPayment = Number(shippingAddress['plannedDownPayment'] ?? 0);

  const ensurePlannedDownpaymentColumn = async (): Promise<boolean> => {
    try {
      await pool.query(
        `ALTER TABLE orders
         ADD COLUMN planned_downpayment_amount DECIMAL(12,2) NOT NULL DEFAULT 0
         COMMENT 'Planned first GCash tranche for down-payment checkout'`,
      );
      return true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes('Duplicate column') || msg.toLowerCase().includes('duplicate column name')) {
        return true;
      }
      console.warn('ensurePlannedDownpaymentColumn:', msg);
      return false;
    }
  };

  const hasPlannedDownColumn = await ensurePlannedDownpaymentColumn();

  // Insert order with downpayment tracking for GCash orders
  // Note: If downpayment_amount and remaining_balance columns don't exist yet,
  // you'll need to run the migration script: app/sql/add_downpayment_columns.sql
  // payment_plan column: app/sql/add_order_plan_id_and_payment_status.sql
  // order_option: app/sql/add_order_option_estimated_delivery.sql
  const insertParamsBase = [
    id,
    input.userId,
    contactName,
    contactPhone,
    shippingLabel,
    shippingLine1,
    shippingLine2,
    shippingRegion,
    shippingPostal,
    subtotalAmount,
    shippingFee,
    input.totalAmount,
    downpayment,
    remainingBalance,
    status,
    paymentMethod,
    paymentPlan ?? null,
  ];

  const ensureTermsVersionAcceptedAtOrderColumn = async (): Promise<boolean> => {
    try {
      await pool.query(
        `ALTER TABLE orders
         ADD COLUMN terms_version_accepted_at_order INT NULL DEFAULT NULL
         COMMENT 'Terms version accepted at order creation time'`,
      );
      return true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes('Duplicate column') || msg.toLowerCase().includes('duplicate column name')) {
        return true;
      }
      console.warn('ensureTermsVersionAcceptedAtOrderColumn:', msg);
      return false;
    }
  };

  // Best-effort: if DB can alter, we persist the snapshot; if not, orders still work.
  const hasTermsSnapshotColumn = await ensureTermsVersionAcceptedAtOrderColumn();

  // One DB transaction: order + line items + inventory reservation must commit together.
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    try {
      if (hasTermsSnapshotColumn) {
        await conn.query(
          `INSERT INTO orders (
            id, user_id, contact_name, contact_phone, shipping_label,
            shipping_line1, shipping_line2, shipping_region, shipping_postal,
            subtotal_amount, shipping_fee, total_amount, downpayment_amount, remaining_balance,
            status, payment_method, payment_plan, order_option, payment_status,
            terms_version_accepted_at_order,
            created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NOW(), NOW())`,
          [
            ...insertParamsBase,
            orderOption ?? null,
            input.termsVersionAcceptedAtOrder ?? null,
          ],
        );
      } else {
        await conn.query(
          `INSERT INTO orders (
            id, user_id, contact_name, contact_phone, shipping_label, 
            shipping_line1, shipping_line2, shipping_region, shipping_postal,
            subtotal_amount, shipping_fee, total_amount, downpayment_amount, remaining_balance,
            status, payment_method, payment_plan, order_option, payment_status, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), NOW())`,
          [...insertParamsBase, orderOption ?? null],
        );
      }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes('order_option') || msg.includes('Unknown column')) {
      try {
        await conn.query(
          `INSERT INTO orders (
            id, user_id, contact_name, contact_phone, shipping_label, 
            shipping_line1, shipping_line2, shipping_region, shipping_postal,
            subtotal_amount, shipping_fee, total_amount, downpayment_amount, remaining_balance,
            status, payment_method, payment_plan, payment_status, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), NOW())`,
          insertParamsBase,
        );
      } catch (e2) {
        const msg2 = e2 instanceof Error ? e2.message : String(e2);
        if (msg2.includes('payment_plan') || msg2.includes('Unknown column')) {
          await conn.query(
            `INSERT INTO orders (
              id, user_id, contact_name, contact_phone, shipping_label, 
              shipping_line1, shipping_line2, shipping_region, shipping_postal,
              subtotal_amount, shipping_fee, total_amount, downpayment_amount, remaining_balance,
              status, payment_method, payment_status, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), NOW())`,
            [
              id,
              input.userId,
              contactName,
              contactPhone,
              shippingLabel,
              shippingLine1,
              shippingLine2,
              shippingRegion,
              shippingPostal,
              subtotalAmount,
              shippingFee,
              input.totalAmount,
              downpayment,
              remainingBalance,
              status,
              paymentMethod,
            ],
          );
        } else {
          throw e2;
        }
      }
    } else if (msg.includes('payment_plan') || msg.includes('Unknown column')) {
      await conn.query(
        `INSERT INTO orders (
          id, user_id, contact_name, contact_phone, shipping_label, 
          shipping_line1, shipping_line2, shipping_region, shipping_postal,
          subtotal_amount, shipping_fee, total_amount, downpayment_amount, remaining_balance,
          status, payment_method, payment_status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), NOW())`,
        [
          id,
          input.userId,
          contactName,
          contactPhone,
          shippingLabel,
          shippingLine1,
          shippingLine2,
          shippingRegion,
          shippingPostal,
          subtotalAmount,
          shippingFee,
          input.totalAmount,
          downpayment,
          remainingBalance,
          status,
          paymentMethod,
        ],
      );
    } else {
      throw e;
    }
  }

  if (hasPlannedDownColumn && plannedDownPayment > 0) {
    try {
      await conn.query(
        `UPDATE orders SET planned_downpayment_amount = ? WHERE id = ?`,
        [plannedDownPayment, id],
      );
    } catch (e) {
      console.warn('planned_downpayment_amount update skipped:', e);
    }
  }

  // Insert order items — explicit lines (MTO), orderLines, or legacy productIds.
  if (input.lineItemsOverride != null && input.lineItemsOverride.length > 0) {
    for (const line of input.lineItemsOverride) {
      await insertOrderItem(conn, {
        orderId: id,
        productId: line.productId,
        variantId: line.variantId ?? null,
        productName: line.productName,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        lineTotal: line.lineTotal,
      });
    }
  } else if (input.orderLines != null && input.orderLines.length > 0) {
    for (const line of input.orderLines) {
      const [productRows] = await conn.query<RowDataPacket[]>(
        'SELECT name, price FROM products WHERE id = ? LIMIT 1',
        [line.productId],
      );
      if (productRows.length === 0) {
        throw new Error(`Product not found: ${line.productId}`);
      }
      const productName = productRows[0].name as string;
      const unitPrice = Number(productRows[0].price);
      const quantity = Math.max(1, Number(line.quantity) || 1);
      const variantId =
        line.variantId ?? (await resolveDefaultVariantId(conn, line.productId));
      await insertOrderItem(conn, {
        orderId: id,
        productId: line.productId,
        variantId,
        productName,
        quantity,
        unitPrice,
        lineTotal: unitPrice * quantity,
      });
    }
  } else {
    for (const productId of input.productIds) {
      const [productRows] = await conn.query<RowDataPacket[]>(
        'SELECT name, price FROM products WHERE id = ? LIMIT 1',
        [productId],
      );
      if (productRows.length === 0) {
        throw new Error(`Product not found: ${productId}`);
      }
      const productName = productRows[0].name as string;
      const unitPrice = Number(productRows[0].price);
      const quantity = 1;
      const variantId = await resolveDefaultVariantId(conn, productId);

      await insertOrderItem(conn, {
        orderId: id,
        productId,
        variantId,
        productName,
        quantity,
        unitPrice,
        lineTotal: unitPrice * quantity,
      });
    }
  }

    // Reserve stock for catalog/home counts (released on cancel / expire).
    if (!input.skipInventoryReservation) {
      await decrementInventoryForOrder(conn, id);
    }
    await conn.commit();
  } catch (txnErr) {
    await conn.rollback();
    throw txnErr;
  } finally {
    conn.release();
  }

  const [rows] = await pool.query<OrderRow[]>(
    `SELECT o.*, u.full_name AS user_name
     FROM orders o
     LEFT JOIN users u ON o.user_id = u.id
     WHERE o.id = ?`,
    [id],
  );
  if (rows.length === 0) {
    throw new Error('Failed to create order');
  }

  notifyAdminsNewOrderPlaced({
    orderId: id,
    userId: input.userId,
    customerName: contactName,
    totalAmount: input.totalAmount,
    paymentMethod,
    status,
  });

  return await mapOrder(rows[0]);
};

export type UpdateOrderStatusOptions = {
  /** Customer-provided reason when cancelling (stored on `cancellation_reason`). */
  readonly cancellationComment?: string;
};

export const updateOrderStatus = async (
  orderId: string,
  status: string,
  options?: UpdateOrderStatusOptions,
): Promise<void> => {
  const pool = getPool();
  
  // Get order details before updating
  const [orderRows] = await pool.query<OrderRow[]>(
    'SELECT * FROM orders WHERE id = ? LIMIT 1',
    [orderId],
  );
  
  if (orderRows.length === 0) {
    throw new Error('Order not found');
  }
  
  const previousStatus = orderRows[0].status;
  const orderTotal = Number(orderRows[0].total_amount);
  const userId = orderRows[0].user_id;

  // Business rules depend on `order_option` + payment completion.
  const normalizedOption = normalizeOrderOption(orderRows[0].order_option);
  const isHulugan = normalizedOption === 'hulugan';
  const isLayaway = normalizedOption === 'layaway';

  const remaining = Number(orderRows[0].remaining_balance ?? 0);
  const paymentStatus = orderRows[0].payment_status?.toString().toLowerCase() ?? 'pending';
  const paymentCompleted = paymentStatus === 'completed' || remaining <= 0.01;

  // Delivery gating for admin-managed transitions.
  if (status === 'shipped' || status === 'delivered') {
    // Hard rule requested: shipping is only allowed when remaining balance is fully cleared.
    // We intentionally key this to `remaining_balance`, not just `payment_status`, so stale
    // status labels can never bypass fulfillment gating.
    if (remaining > 0.01) {
      if (isLayaway) {
        throw new Error('Lay-away orders can only be shipped/delivered when remaining balance is ₱0.');
      }
      if (isHulugan) {
        throw new Error('Installment orders can only be shipped/delivered when remaining balance is ₱0.');
      }
      throw new Error('Orders can only be shipped/delivered when remaining balance is ₱0.');
    }

    // Extra safety for older rows where remaining might be 0 but payment status is still stale.
    if (!paymentCompleted) {
      throw new Error('Orders can only be shipped/delivered after payment is completed.');
    }
  }

  /**
   * **Confirmed** (admin): plan-specific gates enforced above; side effects in applyOrderConfirmed.
   */

  if (status === 'confirmed' && previousStatus !== 'confirmed') {
    const paymentPlan = orderRows[0].payment_plan?.toString().toLowerCase() ?? 'full';
    const downpaymentAmount = Number(orderRows[0].downpayment_amount ?? 0);
    const totalPaid = totalPaidFromOrder(orderTotal, remaining);
    const isMto = await isMtoOrder(pool, orderId);

    if (paymentStatus === 'pending' || paymentStatus === 'failed') {
      throw new Error(
        'Cannot confirm order until payment has been verified. Use Confirm Payment after reviewing the proof.',
      );
    }

    if (paymentPlan === 'full') {
      if (!paymentCompleted) {
        throw new Error('Full-payment orders must be fully paid before confirmation.');
      }
    } else if (isHulugan) {
      const threshold = huluganConfirmThreshold(orderTotal);
      if (totalPaid < threshold - 0.01) {
        throw new Error(
          `Installment orders require at least ${HULUGAN_CONFIRM_PERCENT}% (₱${threshold.toLocaleString('en-PH')}) approved before confirmation.`,
        );
      }
      if (
        paymentStatus !== 'downpayment_received' &&
        paymentStatus !== 'downpayment_paid' &&
        paymentStatus !== 'completed'
      ) {
        throw new Error('Confirm the customer\'s down payment before processing this order.');
      }
    } else if (isLayaway || isMto) {
      if (remaining > 0.01) {
        throw new Error(
          isMto
            ? 'Made-to-order items can only be confirmed after 100% payment is approved.'
            : 'Lay-away orders can only be confirmed after 100% payment is approved.',
        );
      }
      if (!paymentCompleted) {
        throw new Error('Order must be fully paid before confirmation.');
      }
    } else if (paymentPlan === 'downpayment') {
      if (downpaymentAmount < MIN_DOWN_PAYMENT_PESOS) {
        throw new Error(
          `Down payment must be at least ₱${MIN_DOWN_PAYMENT_PESOS.toLocaleString('en-PH')} before the order can be confirmed.`,
        );
      }
      if (remaining > 0.01) {
        throw new Error('Remaining balance must be zero before this order can be confirmed.');
      }
    } else if (!paymentCompleted) {
      throw new Error('Full-payment orders must be fully paid before confirmation.');
    }

    await applyOrderConfirmed(pool, orderId, orderRows[0]);
  } else if (status === 'delivered') {
    try {
      await pool.query(
        `UPDATE orders
         SET status = ?,
             actual_delivery_at = COALESCE(actual_delivery_at, NOW()),
             updated_at = NOW()
         WHERE id = ?`,
        [status, orderId],
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes('actual_delivery_at') || msg.includes('Unknown column')) {
        await pool.query('UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?', [
          status,
          orderId,
        ]);
      } else {
        throw e;
      }
    }
  } else if (
    options?.cancellationComment != null &&
    options.cancellationComment.trim().length > 0
  ) {
    const reason = options.cancellationComment.trim().slice(0, 500);
    await pool.query(
      `UPDATE orders SET status = ?, cancellation_reason = ?, updated_at = NOW() WHERE id = ?`,
      [status, reason, orderId],
    );
  } else {
    await pool.query('UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?', [status, orderId]);
  }

  /**
   * Cancel / expire → return reserved units to `products` (after status row is persisted).
   * Skips double-restore when coming from another terminal state.
   */
  if (shouldReleaseReservedInventory(previousStatus, status)) {
    try {
      await restoreInventoryForOrder(pool, orderId);
    } catch (invErr) {
      console.error(`restoreInventoryForOrder failed for ${orderId}:`, invErr);
    }
  }

  if (shouldRestoreMaterials(previousStatus, status)) {
    try {
      await restoreMaterialsForOrder(pool, orderId);
    } catch (matErr) {
      console.error(`restoreMaterialsForOrder failed for ${orderId}:`, matErr);
    }
  }

  // Send email notification when order is marked as expired
  if (status === 'expired' && previousStatus !== 'expired') {
    EmailService.sendOrderExpiredEmail(userId, orderId).catch((error) => {
      console.error('Failed to send expired-order email:', error);
    });
  }

  if (status === 'shipped' && previousStatus !== 'shipped') {
    EmailService.sendOrderShippedEmail(userId, orderId).catch((error) => {
      console.error('Failed to send shipped-order email:', error);
    });
  }

  if (status === 'delivered' && previousStatus !== 'delivered') {
    EmailService.sendOrderDeliveredEmail(userId, orderId).catch((error) => {
      console.error('Failed to send delivered-order email:', error);
    });
  }

  if (status === 'cancelled' && previousStatus !== 'cancelled') {
    const cancellationReason = orderRows[0].cancellation_reason ?? null;
    const downpaymentAmount = Number(orderRows[0].downpayment_amount ?? 0);

    if (cancellationReason === 'payment_default_non_payment_6_months') {
      EmailService.sendPaymentDefaultCancelledEmail({
        userId,
        orderId,
        depositAmount: downpaymentAmount,
      }).catch((error) => {
        console.error('Failed to send payment-default cancellation email:', error);
      });
    } else {
      EmailService.sendOrderCancelledEmail(userId, orderId).catch((error) => {
        console.error('Failed to send cancelled-order email:', error);
      });
    }

    EmailService.sendAdminEventEmail({
      title: 'Order cancelled',
      message: 'A customer order was cancelled and may need follow-up.',
      details: [
        { label: 'Order ID', value: orderId },
        { label: 'User ID', value: userId },
        { label: 'Previous status', value: previousStatus },
        { label: 'Amount', value: `PHP ${orderTotal.toFixed(2)}` },
        { label: 'Cancellation reason', value: cancellationReason ?? 'n/a' },
      ],
    }).catch((error) => {
      console.error('Failed to send admin cancellation alert email:', error);
    });
  }

  // Keep customer notifications centralized in the same write path so all status
  // changes (admin actions, policy jobs, and route-level transitions) emit push updates.
  notifyUserOrderStatusChanged({
    userId,
    orderId,
    previousStatus,
    nextStatus: status,
  }).catch((error) => {
    console.error('Failed to send order status push notification:', error);
  });
};

/**
 * Upload payment proof for an order
 * Updates order with payment proof URL and sets status to pending_payment_verification
 */
export const uploadPaymentProof = async (
  orderId: string,
  proofUrl: string,
): Promise<void> => {
  const pool = getPool();
  await ensureOrderFulfillmentSchema(pool);

  const [orderRows] = await pool.query<OrderRow[]>(
    'SELECT * FROM orders WHERE id = ? LIMIT 1',
    [orderId],
  );

  if (orderRows.length === 0) {
    throw new Error('Order not found');
  }

  const order = orderRows[0];
  const status = order.status?.toString().toLowerCase() ?? 'pending';
  const remaining = Number(order.remaining_balance ?? order.total_amount);
  const paymentStatus = order.payment_status?.toString().toLowerCase() ?? 'pending';

  if (status === 'cancelled' || status === 'expired') {
    throw new Error('Cannot upload payment proof for a cancelled order');
  }

  if (status === 'confirmed' || status === 'shipped' || status === 'delivered') {
    throw new Error('Order is already confirmed');
  }

  if (paymentStatus === 'completed' || remaining <= 0.01) {
    throw new Error('This order has no outstanding balance to pay');
  }

  const allowedUploadStatuses = new Set([
    'pending',
    'reserved',
    'in_progress',
    'pending_payment_verification',
  ]);
  if (!allowedUploadStatuses.has(status)) {
    throw new Error('Payment proof cannot be uploaded for this order status');
  }

  try {
    await pool.query(
      `UPDATE orders
       SET status = 'pending_payment_verification',
           payment_proof_url = ?,
           updated_at = NOW()
       WHERE id = ?`,
      [proofUrl, orderId],
    );
  } catch (error) {
    await pool.query(
      `UPDATE orders
       SET status = 'pending_payment_verification',
           updated_at = NOW()
       WHERE id = ?`,
      [orderId],
    );
    console.warn(
      `⚠️ payment_proof_url column not found. Run migration: app/sql/add_payment_proof_url_column.sql`,
    );
  }

  console.log(`📸 Payment proof uploaded for order ${orderId}: ${proofUrl}`);

  notifyAdminsPaymentProofUploaded({
    orderId,
    userId: order.user_id,
    totalAmount: Number(order.total_amount),
    paymentMethod: String(order.payment_method ?? 'unknown'),
  });
};

/** Minimum first tranche for down-payment plans (₱3,000 policy). */
const MIN_DOWN_PAYMENT_PESOS = 3000;

export type ConfirmPaymentInput = {
  readonly appliedAmount?: number;
  readonly remainingBalance?: number;
  readonly estimatedDeliveryAt?: string;
};

/**
 * Admin confirms payment proof and updates balances incrementally.
 * Calls evaluateOrderAfterPaymentApproval to apply plan-specific status + ETA rules.
 */
export const confirmPayment = async (
  orderId: string,
  adminId: string,
  input?: ConfirmPaymentInput,
): Promise<OrderRecord> => {
  const pool = getPool();
  await ensureOrderFulfillmentSchema(pool);

  const [orderRows] = await pool.query<OrderRow[]>(
    'SELECT * FROM orders WHERE id = ? LIMIT 1',
    [orderId],
  );

  if (orderRows.length === 0) {
    throw new Error('Order not found');
  }

  const order = orderRows[0];
  const paymentMethod = order.payment_method;
  const userId = order.user_id;
  const orderTotal = Number(order.total_amount);
  const paymentPlan = (order.payment_plan ?? 'full').toString().toLowerCase();
  const currentDown = Number(order.downpayment_amount ?? 0);
  const currentRem = Number(order.remaining_balance ?? orderTotal);
  const isDownPaymentPlan = paymentPlan === 'downpayment';

  let appliedAmount: number;
  let newRemaining: number;

  if (!isDownPaymentPlan) {
    appliedAmount = orderTotal;
    newRemaining = 0;
  } else if (input?.remainingBalance != null && Number.isFinite(input.remainingBalance)) {
    newRemaining = Math.max(0, Number(input.remainingBalance.toFixed(2)));
    appliedAmount = Math.max(0, Number((currentRem - newRemaining).toFixed(2)));
  } else if (input?.appliedAmount != null && Number.isFinite(input.appliedAmount)) {
    appliedAmount = Math.max(0, Number(input.appliedAmount.toFixed(2)));
    newRemaining = Math.max(0, Number((currentRem - appliedAmount).toFixed(2)));
  } else if (currentDown > 0.01 && currentRem > 0.01) {
    appliedAmount = currentRem;
    newRemaining = 0;
  } else {
    const plannedDown = Number(order.planned_downpayment_amount ?? 0);
    appliedAmount =
      plannedDown >= MIN_DOWN_PAYMENT_PESOS
        ? Math.min(plannedDown, orderTotal)
        : Math.max(MIN_DOWN_PAYMENT_PESOS, Math.min(currentRem, orderTotal));
    newRemaining = Math.max(0, Number((orderTotal - currentDown - appliedAmount).toFixed(2)));
    if (currentDown < 0.01) {
      newRemaining = Math.max(0, Number((orderTotal - appliedAmount).toFixed(2)));
    }
  }

  if (appliedAmount < 0.01) {
    throw new Error('Approved payment amount must be greater than zero');
  }
  if (currentDown + appliedAmount > orderTotal + 0.01) {
    throw new Error('Approved payments cannot exceed the order total');
  }
  if (newRemaining < 0) {
    throw new Error('Remaining balance cannot be negative');
  }

  const newDown = Number((currentDown + appliedAmount).toFixed(2));
  const reconciledRemaining = Math.max(0, Number((orderTotal - newDown).toFixed(2)));
  newRemaining = input?.remainingBalance != null ? newRemaining : reconciledRemaining;

  if (isDownPaymentPlan && currentDown < 0.01 && appliedAmount < MIN_DOWN_PAYMENT_PESOS) {
    throw new Error(
      `Down payment must be at least ₱${MIN_DOWN_PAYMENT_PESOS.toLocaleString('en-PH')} before payment can be confirmed.`,
    );
  }

  const paymentStatus =
    newRemaining <= 0.01
      ? 'completed'
      : paymentMethod === 'cod'
        ? 'downpayment_paid'
        : 'downpayment_received';

  const finalPaymentStatus = isDownPaymentPlan ? paymentStatus : 'completed';
  const finalRemaining = isDownPaymentPlan ? newRemaining : 0;
  const finalDown = isDownPaymentPlan ? newDown : orderTotal;

  try {
    await pool.query(
      `UPDATE orders
       SET payment_status = ?,
           downpayment_amount = ?,
           remaining_balance = ?,
           payment_proof_url = NULL,
           first_installment_paid_at = COALESCE(first_installment_paid_at, NOW()),
           updated_at = NOW()
       WHERE id = ?`,
      [finalPaymentStatus, finalDown, finalRemaining, orderId],
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes('first_installment_paid_at') || msg.includes('Unknown column')) {
      await pool.query(
        `UPDATE orders
         SET payment_status = ?,
             downpayment_amount = ?,
             remaining_balance = ?,
             payment_proof_url = NULL,
             updated_at = NOW()
         WHERE id = ?`,
        [finalPaymentStatus, finalDown, finalRemaining, orderId],
      );
    } else if (msg.includes('payment_proof_url') || msg.includes('Unknown column')) {
      await pool.query(
        `UPDATE orders
         SET payment_status = ?,
             downpayment_amount = ?,
             remaining_balance = ?,
             updated_at = NOW()
         WHERE id = ?`,
        [finalPaymentStatus, finalDown, finalRemaining, orderId],
      );
    } else {
      throw e;
    }
  }

  await logAdminPaymentEvent(pool, orderId, appliedAmount, adminId);

  console.log(`✅ Payment confirmed by admin ${adminId} for order ${orderId}`);

  EmailService.sendPaymentConfirmationEmail(userId, orderId, appliedAmount, paymentMethod).catch(
    (error) => {
      console.error('Failed to send payment confirmation email:', error);
    },
  );

  if (finalPaymentStatus === 'completed') {
    EmailService.sendAdminEventEmail({
      title: 'Order Fully Paid',
      message: `Order #${orderId.substring(0, 8).toUpperCase()} was fully paid and verified by admin.`,
      details: [
        { label: 'Order ID', value: orderId },
        { label: 'Admin ID', value: adminId },
        { label: 'Amount', value: `₱${orderTotal.toFixed(2)}` },
        { label: 'Method', value: paymentMethod },
      ],
    }).catch((error) => {
      console.error('Failed to send admin full-payment alert email:', error);
    });
  }

  await evaluateOrderAfterPaymentApproval(orderId, {
    estimatedDeliveryAt: input?.estimatedDeliveryAt ?? null,
  });

  const updated = await getOrderById(orderId);
  if (!updated) {
    throw new Error('Order not found after payment confirmation');
  }
  return updated;
};

const parseEnvPositiveInt = (key: string, fallback: number): number => {
  const raw = process.env[key];
  if (raw == null || String(raw).trim() === '') return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.floor(n);
};

/** Optional column so we only send one “complete payment” email per order. */
const ensureCheckoutReminderColumn = async (pool: Pool): Promise<boolean> => {
  try {
    await pool.query(
      'ALTER TABLE orders ADD COLUMN checkout_reminder_sent_at TIMESTAMP NULL DEFAULT NULL',
    );
    return true;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes('Duplicate column') || msg.toLowerCase().includes('duplicate column name')) {
      return true;
    }
    console.warn('ensureCheckoutReminderColumn:', msg);
    return false;
  }
};

/**
 * PayMongo lifecycle: order + inventory reservation happen at checkout (create order).
 * - After [ORDER_PAYMENT_REMINDER_MINUTES], send one reminder email (if column exists).
 * - After [ORDER_PAYMENT_HOLD_RELEASE_MINUTES] (default 24h), cancel unpaid orders and restore inventory.
 *
 * Closing PayMongo checkout does NOT cancel — users can retry from Orders within the hold window.
 * Lay-away / installment orders with a received down payment are excluded.
 */
export const autoCancelUnpaidOrders = async (): Promise<number> => {
  const pool = getPool();
  const hasReminderCol = await ensureCheckoutReminderColumn(pool);

  const reminderMin = parseEnvPositiveInt('ORDER_PAYMENT_REMINDER_MINUTES', 12 * 60);
  const cancelMin = parseEnvPositiveInt('ORDER_PAYMENT_HOLD_RELEASE_MINUTES', 24 * 60);
  if (cancelMin <= reminderMin) {
    console.warn(
      `ORDER_PAYMENT_HOLD_RELEASE_MINUTES (${cancelMin}) should be greater than ORDER_PAYMENT_REMINDER_MINUTES (${reminderMin})`,
    );
  }

  if (hasReminderCol) {
    try {
      const [reminderRows] = await pool.query<RowDataPacket[]>(
        `SELECT id, user_id, total_amount FROM orders
         WHERE status = 'pending'
           AND LOWER(COALESCE(payment_status, 'pending')) = 'pending'
           AND payment_method IN ('gcash', 'cod', 'paymongo')
           AND (payment_proof_url IS NULL OR payment_proof_url = '')
           AND TIMESTAMPDIFF(MINUTE, created_at, NOW()) >= ?
           AND TIMESTAMPDIFF(MINUTE, created_at, NOW()) < ?
           AND checkout_reminder_sent_at IS NULL`,
        [reminderMin, cancelMin],
      );
      let sent = 0;
      for (const row of reminderRows) {
        const oid = row.id as string;
        const uid = row.user_id as string;
        const total = Number(row.total_amount);
        await EmailService.sendPendingPaymentReminderEmail(uid, oid, total);
        await pool.query(
          `UPDATE orders SET checkout_reminder_sent_at = NOW(), updated_at = NOW() WHERE id = ?`,
          [oid],
        );
        sent += 1;
      }
      if (sent > 0) {
        console.log(`📧 Sent ${sent} checkout payment reminder(s)`);
      }
    } catch (e) {
      console.warn('checkout reminder batch skipped:', e);
    }
  }

  const [cancelRows] = await pool.query<RowDataPacket[]>(
    `SELECT id FROM orders
     WHERE status = 'pending'
       AND LOWER(COALESCE(payment_status, 'pending')) = 'pending'
       AND payment_method IN ('gcash', 'cod', 'paymongo')
       AND (payment_proof_url IS NULL OR payment_proof_url = '')
       AND TIMESTAMPDIFF(MINUTE, created_at, NOW()) >= ?`,
    [cancelMin],
  );

  let cancelled = 0;
  for (const row of cancelRows) {
    const oid = row.id as string;
    try {
      await updateOrderStatus(oid, 'cancelled', {
        cancellationComment:
          'Payment not completed within 24 hours (automatic cancellation)',
      });
      await pool.query(`UPDATE orders SET payment_status = 'failed', updated_at = NOW() WHERE id = ?`, [oid]);
      cancelled += 1;
    } catch (e) {
      console.error(`auto-cancel failed for ${oid}:`, e);
    }
  }
  return cancelled;
};




