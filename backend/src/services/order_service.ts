import { RowDataPacket, ResultSetHeader } from 'mysql2';
import type { Connection, Pool } from 'mysql2/promise';
import { getPool } from '../config/database';
import { OrderRecord } from '../models/order_record';
import { parseJsonRecord, parseStringArray } from '../utils/parser';
import { EmailService } from './email_service';
import { ensureInvoiceTables } from './order_invoice_service';

type OrderRow = RowDataPacket & {
  readonly id: string;
  readonly user_id: string;
  readonly user_name: string | null;
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
  readonly status: string;
  readonly payment_method: string;
  /** full | downpayment — nullable if migration not applied */
  readonly payment_plan?: string | null;
  /** layaway | hulugan — down-payment checkout path */
  readonly order_option?: string | null;
  readonly payment_status: string;
  readonly payment_proof_url: string | null;
  readonly valid_id_proof_url?: string | null;
  readonly cancellation_reason?: string | null;
  readonly payment_default_cancelled_at?: Date | string | null;
  readonly payment_default_warn_2m_sent_at?: Date | string | null;
  readonly payment_default_warn_80d_sent_at?: Date | string | null;
  readonly payment_default_warn_90d_sent_at?: Date | string | null;
  /** Set when first PayMongo tranche (down payment) posts — 3-month policy window starts here */
  readonly first_installment_paid_at?: Date | string | null;
  readonly estimated_delivery_at?: Date | string | null;
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
    createdAt: createdAt,
    updatedAt: updatedAt,
  };
};

export const listOrders = async (): Promise<OrderRecord[]> => {
  const pool = getPool();
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

const approxEqualPesos = (a: number, b: number): boolean => Math.abs(a - b) < 1.0;

/**
 * First PayMongo tranche succeeded: mark down payment received and anchor `first_installment_paid_at`
 * (3-month policy window). Tolerates missing ENUM value or missing migration column.
 */
const trySetDownpaymentReceived = async (pool: Pool, orderId: string): Promise<void> => {
  const withAnchor = `UPDATE orders SET
    payment_status = 'downpayment_received',
    status = 'pending',
    first_installment_paid_at = COALESCE(first_installment_paid_at, NOW()),
    updated_at = NOW()
  WHERE id = ?`;
  const withoutAnchor = `UPDATE orders SET
    payment_status = 'downpayment_received',
    status = 'pending',
    updated_at = NOW()
  WHERE id = ?`;
  const fallbackPending = `UPDATE orders SET
    payment_status = 'pending',
    status = 'pending',
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
  const dp = Number(row.downpayment_amount ?? 0);
  const plan = row.payment_plan ?? null;
  const paidAmount = options?.amountPesos ?? null;
  const eventId = options?.eventId ?? null;
  const isDownPlan = plan === 'downpayment';

  // Idempotency guard: if we already processed this exact webhook event for a PayMongo order,
  // don't subtract remaining again.
  if (eventId != null && row.payment_proof_url === eventId) {
    console.log(`PayMongo webhook: duplicate event ${eventId} for order ${orderId} — ignored`);
    return;
  }

  const looksLikeInstallmentStructure = rem > 0.01 && dp < orderTotal - 0.01;

  /**
   * Single full PayMongo charge (full plan, or order total equals downpayment line).
   */
  const treatAsSingleFullPayment = !isDownPlan || !looksLikeInstallmentStructure;

  if (treatAsSingleFullPayment) {
    await pool.query(
      `UPDATE orders
       SET status = 'confirmed',
           payment_status = 'completed',
           remaining_balance = 0,
           updated_at = NOW()
       WHERE id = ?`,
      [orderId],
    );
    if (eventId != null) {
      try {
        await pool.query(`UPDATE orders SET payment_proof_url = ?, updated_at = NOW() WHERE id = ?`, [
          eventId,
          orderId,
        ]);
      } catch {
        // Ignore idempotency storage failures; payment update is already done.
      }
    }
    // Lay-away / one-shot full pay: ETA starts at full settlement (Hulugan one-shot included).
    await trySetEstimatedDeliveryAfterFullPaymentIfNeeded(pool, orderId);
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

    if (previousStatus !== 'confirmed') {
      EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
        console.error('Failed to send order confirmation email (PayMongo):', error);
      });
    }
    return;
  }

  // --- Two-phase down payment plan ---
  if (paidAmount != null) {
    if (row.payment_status === 'pending' && approxEqualPesos(paidAmount, dp)) {
      await trySetDownpaymentReceived(pool, orderId);
      // Hulugan: required DP clears production/shipping clock (10–12d from first tranche).
      if (normalizeOrderOption(row.order_option) === 'hulugan') {
        await trySetHuluganEstimatedDeliveryAfterDownPayment(pool, orderId);
      }
      // Store webhook event id for idempotency (prevents duplicate first-tranche webhooks).
      if (eventId != null) {
        try {
          await pool.query(`UPDATE orders SET payment_proof_url = ?, updated_at = NOW() WHERE id = ?`, [
            eventId,
            orderId,
          ]);
        } catch {
          // ignore
        }
      }
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
        if (eventId != null) {
          try {
            await pool.query(`UPDATE orders SET payment_proof_url = ?, updated_at = NOW() WHERE id = ?`, [
              eventId,
              orderId,
            ]);
          } catch {
            // ignore
          }
        }
      };

      // Paying essentially all of `remaining_balance` while the row still says `pending`:
      // treat as the final tranche (stale state after an earlier DP).
      if (approxEqualPesos(paidAmount, rem)) {
        await pool.query(
          `UPDATE orders
           SET status = 'confirmed',
               payment_status = 'completed',
               remaining_balance = 0,
               updated_at = NOW()
           WHERE id = ?`,
          [orderId],
        );
        await persistEventId();
        await trySetEstimatedDeliveryAfterFullPaymentIfNeeded(pool, orderId);
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

        if (previousStatus !== 'confirmed') {
          EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
            console.error('Failed to send order confirmation email (PayMongo balance):', error);
          });
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
             updated_at = NOW()
         WHERE id = ?`,
        [newRemaining, orderId],
      );
      if (normalizeOrderOption(row.order_option) === 'hulugan') {
        await trySetHuluganEstimatedDeliveryAfterDownPayment(pool, orderId);
      }
      await persistEventId();
      console.log(
        `✅ PayMongo pending plan payment for ${orderId}: paid=${paidAmount}, newRemaining=${newRemaining}`,
      );

      if (newRemaining <= 0.01) {
        await pool.query(
          `UPDATE orders
           SET status = 'confirmed',
               payment_status = 'completed',
               remaining_balance = 0,
               updated_at = NOW()
           WHERE id = ?`,
          [orderId],
        );
        await trySetEstimatedDeliveryAfterFullPaymentIfNeeded(pool, orderId);
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

      if (newRemaining <= 0.01 && previousStatus !== 'confirmed') {
        EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
          console.error('Failed to send order confirmation email (PayMongo balance):', error);
        });
      }
      return;
    }

    if (row.payment_status === 'downpayment_received' && approxEqualPesos(paidAmount, rem)) {
      await pool.query(
        `UPDATE orders
         SET status = 'confirmed',
             payment_status = 'completed',
             remaining_balance = 0,
             updated_at = NOW()
         WHERE id = ?`,
        [orderId],
      );
      if (eventId != null) {
        try {
          await pool.query(`UPDATE orders SET payment_proof_url = ?, updated_at = NOW() WHERE id = ?`, [
            eventId,
            orderId,
          ]);
        } catch {
          // ignore
        }
      }
      // Lay-away second tranche (or non-hulugan): ETA from final payment; hulugan keeps DP-based ETA.
      await trySetEstimatedDeliveryAfterFullPaymentIfNeeded(pool, orderId);
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

      if (previousStatus !== 'confirmed') {
        EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
          console.error('Failed to send order confirmation email (PayMongo balance):', error);
        });
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
             payment_status = 'downpayment_received',
             updated_at = NOW()
         WHERE id = ?`,
        [newRemaining, orderId],
      );

      if (eventId != null) {
        try {
          await pool.query(`UPDATE orders SET payment_proof_url = ?, updated_at = NOW() WHERE id = ?`, [
            eventId,
            orderId,
          ]);
        } catch {
          // ignore
        }
      }

      // If this partial payment actually completes the balance (due to rounding),
      // settle as completed.
      if (newRemaining <= 0.01) {
        await pool.query(
          `UPDATE orders
           SET status = 'confirmed',
               payment_status = 'completed',
               remaining_balance = 0,
               updated_at = NOW()
           WHERE id = ?`,
          [orderId],
        );
        await trySetEstimatedDeliveryAfterFullPaymentIfNeeded(pool, orderId);
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

      return;
    }

    if (row.payment_status === 'downpayment_received' && approxEqualPesos(paidAmount, dp)) {
      console.log(`PayMongo webhook: duplicate first-installment event for ${orderId} — ignored`);
      return;
    }

    if (row.payment_status === 'pending' && approxEqualPesos(paidAmount, orderTotal)) {
      await pool.query(
        `UPDATE orders
         SET status = 'confirmed',
             payment_status = 'completed',
             remaining_balance = 0,
             updated_at = NOW()
         WHERE id = ?`,
        [orderId],
      );
      await trySetEstimatedDeliveryAfterFullPaymentIfNeeded(pool, orderId);
      console.log(`✅ PayMongo full payment (amount matched total) for order ${orderId}`);
      if (previousStatus !== 'confirmed') {
        EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
          console.error('Failed to send order confirmation email (PayMongo):', error);
        });
      }
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
    if (normalizeOrderOption(row.order_option) === 'hulugan') {
      await trySetHuluganEstimatedDeliveryAfterDownPayment(pool, orderId);
    }
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
     SET status = 'confirmed',
         payment_status = 'completed',
         remaining_balance = 0,
         updated_at = NOW()
     WHERE id = ?`,
    [orderId],
  );
  await trySetEstimatedDeliveryAfterFullPaymentIfNeeded(pool, orderId);
  console.log(`✅ PayMongo full payment recorded for order ${orderId} (fallback tail)`);
  if (previousStatus !== 'confirmed') {
    EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
      console.error('Failed to send order confirmation email (PayMongo):', error);
    });
  }
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
   * When set, inserts these order lines instead of resolving prices from [productIds].
   * Used for made-to-order (custom line totals).
   */
  readonly lineItemsOverride?: ReadonlyArray<{
    readonly productId: string;
    readonly productName: string;
    readonly quantity: number;
    readonly unitPrice: number;
    readonly lineTotal: number;
  }>;
}

/** Placeholder SKU so MTO orders reserve one line item without a catalog product. */
export const MTO_PLACEHOLDER_PRODUCT_ID = 'p_made_to_order_placeholder';

export const ensureMadeToOrderPlaceholderProduct = async (pool: Pool): Promise<void> => {
  const [rows] = await pool.query<RowDataPacket[]>(
    'SELECT id FROM products WHERE id = ? LIMIT 1',
    [MTO_PLACEHOLDER_PRODUCT_ID],
  );
  if (rows.length > 0) return;
  await pool.query(
    `INSERT INTO products (
      id, name, description, price, category, style, material, color, model_path,
      inventory_qty, in_stock, is_archived
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      MTO_PLACEHOLDER_PRODUCT_ID,
      'Made-to-Order (Custom)',
      'Placeholder SKU for custom furniture orders.',
      0,
      'Made-to-Order',
      'Custom',
      'Various',
      'Various',
      'assets/chair.glb',
      999999,
      true,
      false,
    ],
  );
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
  await ensureMadeToOrderPlaceholderProduct(pool);
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
    lineItemsOverride: [
      {
        productId: MTO_PLACEHOLDER_PRODUCT_ID,
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

  // Get downpayment amount for GCash orders (20% of total)
  // This is required for GCash payments to verify user authenticity and security
  const downpayment = (shippingAddress['downpayment'] as number) ?? 0;
  const remainingBalance = (shippingAddress['remainingBalance'] as number) ?? input.totalAmount;

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

  // One DB transaction: order + line items + inventory reservation must commit together.
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    try {
      await conn.query(
      `INSERT INTO orders (
        id, user_id, contact_name, contact_phone, shipping_label, 
        shipping_line1, shipping_line2, shipping_region, shipping_postal,
        subtotal_amount, shipping_fee, total_amount, downpayment_amount, remaining_balance,
        status, payment_method, payment_plan, order_option, payment_status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), NOW())`,
      [...insertParamsBase, orderOption ?? null],
    );
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

  // Insert order items — either explicit lines (MTO) or catalog products.
  const { generateId: generateItemId } = await import('../utils/id_generator');
  if (input.lineItemsOverride != null && input.lineItemsOverride.length > 0) {
    for (const line of input.lineItemsOverride) {
      const itemId = generateItemId('oi');
      await conn.query(
        `INSERT INTO order_items (id, order_id, product_id, product_name, quantity, unit_price, line_total)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [itemId, id, line.productId, line.productName, line.quantity, line.unitPrice, line.lineTotal],
      );
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
      const lineTotal = unitPrice * quantity;

      const itemId = generateItemId('oi');
      await conn.query(
        `INSERT INTO order_items (id, order_id, product_id, product_name, quantity, unit_price, line_total)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [itemId, id, productId, productName, quantity, unitPrice, lineTotal],
      );
    }
  }

    // Reserve stock for catalog/home counts (released on cancel / expire).
    await decrementInventoryForOrder(conn, id);
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
  return await mapOrder(rows[0]);
};

export const updateOrderStatus = async (orderId: string, status: string): Promise<void> => {
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
    // Shipping and delivery must wait until the order is fully settled.
    // A down payment is enough for confirmation, but not for fulfillment.
    if (!paymentCompleted) {
      if (isLayaway) {
        throw new Error('Lay-away orders can only be shipped/delivered after full payment.');
      }
      if (isHulugan) {
        throw new Error('Hulugan orders can only be shipped/delivered after the remaining balance is fully paid.');
      }
      throw new Error('Orders can only be shipped/delivered after payment is completed.');
    }
  }

  /**
   * **Confirmed** (admin):
   * - Hulugan: set ETA when confirmed (typically right after down payment).
   * - Lay-away: set ETA only when payment is fully completed; otherwise keep ETA empty.
   *
   * Migration: `estimated_delivery_at` — app/sql/add_order_option_estimated_delivery.sql
   */
  const deliveryOffsetDays = (): number => randomDeliveryOffsetDays();

  if (status === 'confirmed' && previousStatus !== 'confirmed') {
    const shouldSetEta = isHulugan || (isLayaway && paymentCompleted);
    if (shouldSetEta) {
      try {
        await pool.query(
          `UPDATE orders SET status = ?,
             estimated_delivery_at = COALESCE(estimated_delivery_at, DATE_ADD(NOW(), INTERVAL ? DAY)),
             updated_at = NOW()
           WHERE id = ?`,
          [status, deliveryOffsetDays(), orderId],
        );
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        if (msg.includes('estimated_delivery_at') || msg.includes('Unknown column')) {
          await pool.query('UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?', [status, orderId]);
        } else {
          throw e;
        }
      }
    } else {
      await pool.query('UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?', [status, orderId]);
    }
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

  // Send email notification when order is confirmed
  if (status === 'confirmed' && previousStatus !== 'confirmed') {
    // Send email asynchronously (don't wait for it)
    EmailService.sendOrderConfirmationEmail(userId, orderId, orderTotal).catch((error) => {
      console.error('Failed to send confirmation email:', error);
      // Don't throw - email failure shouldn't break order update
    });
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
  
  // Verify order exists
  const [orderRows] = await pool.query<OrderRow[]>(
    'SELECT * FROM orders WHERE id = ? LIMIT 1',
    [orderId],
  );
  
  if (orderRows.length === 0) {
    throw new Error('Order not found');
  }
  
  // Check if order is already cancelled or confirmed
  if (orderRows[0].status === 'cancelled') {
    throw new Error('Cannot upload payment proof for a cancelled order');
  }
  
  if (orderRows[0].status === 'confirmed') {
    throw new Error('Order is already confirmed');
  }
  
  // Update order with payment proof URL and set status to pending verification
  // Try to update payment_proof_url column if it exists, otherwise just update status
  try {
    // Attempt to update with payment_proof_url column (if migration has been run)
    await pool.query(
      `UPDATE orders 
       SET status = 'pending_payment_verification',
           payment_status = 'pending',
           payment_proof_url = ?,
           updated_at = NOW()
       WHERE id = ?`,
      [proofUrl, orderId],
    );
  } catch (error) {
    // If column doesn't exist, update without it
    // This allows the system to work before running the migration
    await pool.query(
      `UPDATE orders 
       SET status = 'pending_payment_verification',
           payment_status = 'pending',
           updated_at = NOW()
       WHERE id = ?`,
      [orderId],
    );
    console.warn(`⚠️ payment_proof_url column not found. Run migration: app/sql/add_payment_proof_url_column.sql`);
  }
  
  console.log(`📸 Payment proof uploaded for order ${orderId}: ${proofUrl}`);
};

/**
 * Admin confirms payment proof and updates order status
 * Sets payment_status to 'downpayment_paid' or 'completed' based on payment method
 * Sends confirmation email to user
 */
export const confirmPayment = async (
  orderId: string,
  adminId: string,
): Promise<void> => {
  const pool = getPool();
  
  // Get order details
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
  
  // Determine payment status based on payment method
  // COD: downpayment_paid (20% paid, 80% remaining)
  // GCash: completed (full payment)
  const paymentStatus = paymentMethod === 'cod' ? 'downpayment_paid' : 'completed';
  const orderStatus = paymentMethod === 'cod' ? 'pending' : 'confirmed';
  
  // Update order payment status
  await pool.query(
    `UPDATE orders 
     SET payment_status = ?,
         status = ?,
         updated_at = NOW()
     WHERE id = ?`,
    [paymentStatus, orderStatus, orderId],
  );
  
  console.log(`✅ Payment confirmed by admin ${adminId} for order ${orderId}`);
  
  // Send confirmation email to user
  EmailService.sendPaymentConfirmationEmail(userId, orderId, orderTotal, paymentMethod).catch((error) => {
    console.error('Failed to send payment confirmation email:', error);
  });
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
 * - After [ORDER_PAYMENT_HOLD_RELEASE_MINUTES], cancel unpaid orders and restore inventory.
 *
 * Cancel return URL still cancels immediately when the user closes PayMongo.
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
         WHERE payment_method = 'paymongo'
           AND status = 'pending'
           AND LOWER(COALESCE(payment_status, 'pending')) = 'pending'
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
     WHERE payment_method = 'paymongo'
       AND status = 'pending'
       AND LOWER(COALESCE(payment_status, 'pending')) = 'pending'
       AND TIMESTAMPDIFF(MINUTE, created_at, NOW()) >= ?`,
    [cancelMin],
  );

  let cancelled = 0;
  for (const row of cancelRows) {
    const oid = row.id as string;
    try {
      await updateOrderStatus(oid, 'cancelled');
      await pool.query(`UPDATE orders SET payment_status = 'failed', updated_at = NOW() WHERE id = ?`, [oid]);
      cancelled += 1;
    } catch (e) {
      console.error(`auto-cancel failed for ${oid}:`, e);
    }
  }
  return cancelled;
};




