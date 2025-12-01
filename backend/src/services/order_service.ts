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
  readonly status: string;
  readonly payment_method: string;
  readonly payment_status: string;
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
  const shippingAddress: Record<string, unknown> = {
    name: row.contact_name,
    phone: row.contact_phone,
    line1: row.shipping_line1,
    line2: row.shipping_line2 ?? '',
    city: row.shipping_region,
    postalCode: row.shipping_postal ?? '',
    label: row.shipping_label ?? 'Home',
  };
  
  return {
    id: row.id,
    userId: row.user_id,
    userName: row.user_name ?? row.contact_name,
    productIds: productIds,
    totalAmount: Number(row.total_amount),
    status: row.status,
    shippingAddress: shippingAddress,
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
  // For now, assume shipping is 20.0 and subtotal is total - shipping
  const shippingFee = 20.0;
  const subtotalAmount = input.totalAmount - shippingFee;

  // Insert order
  await pool.query(
    `INSERT INTO orders (
      id, user_id, contact_name, contact_phone, shipping_label, 
      shipping_line1, shipping_line2, shipping_region, shipping_postal,
      subtotal_amount, shipping_fee, total_amount, status, 
      payment_method, payment_status, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'cod', 'pending', NOW(), NOW())`,
    [
      id, input.userId, contactName, contactPhone, shippingLabel,
      shippingLine1, shippingLine2, shippingRegion, shippingPostal,
      subtotalAmount, shippingFee, input.totalAmount, status,
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
};




