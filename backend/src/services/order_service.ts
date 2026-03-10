import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { OrderRecord } from '../models/order_record';
import { parseJsonRecord, parseStringArray } from '../utils/parser';
import { EmailService } from './email_service';

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
  readonly payment_status: string;
  readonly payment_proof_url: string | null;
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

export interface CreateOrderInput {
  readonly userId: string;
  readonly userName: string;
  readonly productIds: readonly string[];
  readonly totalAmount: number;
  readonly shippingAddress: Record<string, unknown>;
  readonly status?: string;
}

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
  const subtotalAmount = input.totalAmount - shippingFee;
  
  // Get payment method from shipping address, default to 'cod' for backwards compatibility
  const paymentMethod = (shippingAddress['paymentMethod'] as string) ?? 'cod';
  
  // Get downpayment amount for GCash orders (20% of total)
  // This is required for GCash payments to verify user authenticity and security
  const downpayment = (shippingAddress['downpayment'] as number) ?? 0;
  const remainingBalance = (shippingAddress['remainingBalance'] as number) ?? input.totalAmount;

  // Insert order with downpayment tracking for GCash orders
  // Note: If downpayment_amount and remaining_balance columns don't exist yet,
  // you'll need to run the migration script: app/sql/add_downpayment_columns.sql
  await pool.query(
    `INSERT INTO orders (
      id, user_id, contact_name, contact_phone, shipping_label, 
      shipping_line1, shipping_line2, shipping_region, shipping_postal,
      subtotal_amount, shipping_fee, total_amount, downpayment_amount, remaining_balance,
      status, payment_method, payment_status, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NOW(), NOW())`,
    [
      id, input.userId, contactName, contactPhone, shippingLabel,
      shippingLine1, shippingLine2, shippingRegion, shippingPostal,
      subtotalAmount, shippingFee, input.totalAmount, downpayment, remainingBalance,
      status, paymentMethod,
    ],
  );

  // Insert order items - need to fetch product info first
  const { generateId: generateItemId } = await import('../utils/id_generator');
  for (const productId of input.productIds) {
    // Fetch product details
    const [productRows] = await pool.query<RowDataPacket[]>(
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
    await pool.query(
      `INSERT INTO order_items (id, order_id, product_id, product_name, quantity, unit_price, line_total)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [itemId, id, productId, productName, quantity, unitPrice, lineTotal],
    );
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
  
  // Update order status
  await pool.query('UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?', [status, orderId]);
  
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

/**
 * Auto-cancel orders that haven't received payment within 30 minutes
 * This should be called by a cron job or scheduled task
 * 
 * Cancels orders that:
 * - Status is 'pending' or 'pending_payment_verification'
 * - Payment status is 'pending' (no payment proof uploaded or confirmed)
 * - Created more than 30 minutes ago
 */
export const autoCancelUnpaidOrders = async (): Promise<number> => {
  const pool = getPool();
  
  // Find orders that are:
  // 1. Status is 'pending' or 'pending_payment_verification' (not cancelled or confirmed)
  // 2. Payment status is 'pending' (no payment received)
  // 3. Created more than 30 minutes ago
  const [rows] = await pool.query<OrderRow[]>(
    `SELECT id, user_id, total_amount 
     FROM orders 
     WHERE (status = 'pending' OR status = 'pending_payment_verification')
       AND payment_status = 'pending'
       AND created_at < DATE_SUB(NOW(), INTERVAL 30 MINUTE)`,
  );
  
  let cancelledCount = 0;
  
  for (const row of rows) {
    try {
      // Set status to 'expired' instead of 'cancelled' so users can repay
      await pool.query(
        `UPDATE orders 
         SET status = 'expired',
             payment_status = 'failed',
             updated_at = NOW()
         WHERE id = ?`,
        [row.id],
      );
      cancelledCount++;
      console.log(`⏰ Auto-expired order ${row.id} (no payment within 30 minutes)`);

      // Notify user that their order expired
      EmailService.sendOrderExpiredEmail(row.user_id, row.id).catch((error) => {
        console.error(`Failed to send expired-order email for ${row.id}:`, error);
      });
    } catch (error) {
      console.error(`Failed to expire order ${row.id}:`, error);
    }
  }
  
  if (cancelledCount > 0) {
    console.log(`⏰ Auto-expiration: Expired ${cancelledCount} unpaid order(s)`);
  }
  
  return cancelledCount;
};




