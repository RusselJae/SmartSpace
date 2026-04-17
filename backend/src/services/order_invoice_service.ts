import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';

/**
 * Payment events we store so invoices can show:
 * - each payment made (downpayment + subsequent payments)
 * - each late-fee charge applied per day after the 3-month window
 *
 * Note: invoices are "single invoice per order" — one orderId maps to one
 * invoiceNumber (we use orderId directly as the invoice number).
 */
export type OrderPaymentEventRow = RowDataPacket & {
  readonly id: string;
  readonly order_id: string;
  readonly event_type: string;
  readonly amount: number;
  readonly event_time: Date;
  readonly paymongo_event_id: string | null;
};

export type OrderLateFeeEventRow = RowDataPacket & {
  readonly id: string;
  readonly order_id: string;
  readonly fee_date: Date;
  readonly amount: number;
  readonly created_at: Date;
};

type InvoiceVersion = 'deposit_version' | 'progress_version' | 'paid_final';
type InvoiceLineItem = {
  readonly description: string;
  readonly amount: number;
};

export type InvoiceBuildResult = {
  readonly version: InvoiceVersion;
  readonly invoiceNumber: string;
  readonly invoiceTitle: string;
  readonly subject: string;
  readonly bodyHtml: string;
  readonly depositPaid: number;
  readonly totalBalanceDue: number;
  readonly totalLateFees: number;
  readonly paymentEvents: OrderPaymentEventRow[];
  readonly lateFeeEvents: OrderLateFeeEventRow[];
};

const escapeHtml = (value: string): string =>
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

export const ensureInvoiceTables = async (): Promise<void> => {
  const pool = getPool();

  await pool.query(`
    CREATE TABLE IF NOT EXISTS order_payment_events (
      id VARCHAR(64) PRIMARY KEY,
      order_id VARCHAR(50) NOT NULL,
      event_type VARCHAR(40) NOT NULL,
      amount DECIMAL(12,2) NOT NULL,
      event_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      paymongo_event_id VARCHAR(120) NULL,
      source VARCHAR(30) NOT NULL DEFAULT 'paymongo',
      INDEX idx_payment_events_order_time (order_id, event_time)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS order_late_fee_events (
      id VARCHAR(64) PRIMARY KEY,
      order_id VARCHAR(50) NOT NULL,
      fee_date DATE NOT NULL,
      amount DECIMAL(12,2) NOT NULL DEFAULT 100.00,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_late_fee_order_date (order_id, fee_date),
      INDEX idx_late_fee_events_order_date (order_id, fee_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
};

const formatPesos = (n: number): string => `₱${n.toFixed(2)}`;

const shortOrderId = (orderId: string): string => orderId.substring(0, 8).toUpperCase();

const buildInvoiceBodyHtml = (params: {
  readonly version: InvoiceVersion;
  readonly orderId: string;
  readonly invoiceTitle: string;
  readonly customerName: string;
  readonly line1: string;
  readonly city: string;
  readonly invoiceDate: Date;
  readonly customerId: string;
  readonly totalPrice: number;
  readonly depositPaid: number;
  readonly totalBalanceDue: number;
  readonly totalLateFees: number;
  readonly lineItems: readonly InvoiceLineItem[];
  readonly paymentEvents: OrderPaymentEventRow[];
  readonly lateFeeEvents: OrderLateFeeEventRow[];
}): string => {
  const {
    version,
    orderId,
    invoiceTitle,
    customerName,
    line1,
    city,
    invoiceDate,
    customerId,
    totalPrice,
    depositPaid,
    totalBalanceDue,
    totalLateFees,
    lineItems,
    paymentEvents,
    lateFeeEvents,
  } = params;
  const invoiceNumber = orderId;
  const dateLabel = invoiceDate.toISOString().slice(0, 10);
  const lineRows =
    lineItems.length === 0
      ? `<tr><td style="padding:8px 0;color:#4b5563;">Order item</td><td style="padding:8px 0;text-align:right;">${escapeHtml(formatPesos(totalPrice))}</td></tr>`
      : lineItems
          .map(
            (line) => `
          <tr>
            <td style="padding:8px 0;color:#111827;">${escapeHtml(line.description)}</td>
            <td style="padding:8px 0;text-align:right;color:#111827;font-weight:600;">${escapeHtml(formatPesos(line.amount))}</td>
          </tr>`,
          )
          .join('');
  const paidStamp = version === 'paid_final' ? `<div style="margin-top:6px;font-weight:700;color:#16a34a;">PAID</div>` : '';

  return `
      <div style="border:1px solid #e5e7eb;border-radius:10px;padding:16px;background:#fff;">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:16px;">
          <div>
            <div style="font-size:30px;font-weight:800;line-height:1.1;color:#111827;">Wood Home Furniture Trading</div>
            <div style="margin-top:10px;font-size:14px;color:#111827;">${escapeHtml(customerName)}</div>
            <div style="font-size:14px;color:#111827;">${escapeHtml(line1)}</div>
            <div style="font-size:14px;color:#111827;">${escapeHtml(city)}</div>
            ${paidStamp}
          </div>
          <div style="min-width:280px;text-align:left;">
            <div style="font-size:44px;font-weight:800;line-height:1;color:#111827;">Invoice</div>
            <div style="margin-top:10px;font-size:14px;color:#111827;">Invoice #: ${escapeHtml(invoiceNumber)}</div>
            <div style="font-size:14px;color:#111827;">Invoice Date: ${escapeHtml(dateLabel)}</div>
            <div style="font-size:14px;color:#111827;">Invoice Amount: ${escapeHtml(formatPesos(totalPrice))}</div>
            <div style="font-size:14px;color:#111827;">Customer ID: ${escapeHtml(customerId)}</div>
          </div>
        </div>

        <div style="margin-top:14px;border-top:1px solid #d1d5db;"></div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:10px;border-collapse:collapse;">
          <thead>
            <tr>
              <th align="left" style="font-size:14px;color:#111827;font-weight:700;padding:6px 0;">DESCRIPTION</th>
              <th align="right" style="font-size:14px;color:#111827;font-weight:700;padding:6px 0;">AMOUNT</th>
            </tr>
          </thead>
          <tbody>
            ${lineRows}
          </tbody>
        </table>

        <div style="margin-top:12px;display:flex;justify-content:flex-end;">
          <div style="text-align:right;">
            <div style="font-size:15px;color:#111827;">Total: ${escapeHtml(formatPesos(totalPrice))}</div>
            <div style="font-size:24px;font-weight:800;color:#111827;line-height:1.2;">Amount Due: ${escapeHtml(formatPesos(totalBalanceDue))}</div>
          </div>
        </div>

        <div style="margin-top:10px;background:#f3f4f6;border-radius:8px;padding:8px 10px;color:#4b5563;font-size:12px;line-height:1.4;">
          Notes: Please pay your invoice within 6 months of receiving it
        </div>
      </div>
  `;
};

export const buildUpdatedOrderInvoiceHtml = async (orderId: string): Promise<InvoiceBuildResult> => {
  await ensureInvoiceTables();
  const pool = getPool();

  const [orderRows] = await pool.query<any[]>(
    `SELECT 
      id,
      total_amount,
      downpayment_amount,
      remaining_balance,
      payment_status,
      payment_plan,
      user_id,
      contact_name,
      shipping_line1,
      shipping_region,
      created_at
     FROM orders
     WHERE id = ?
     LIMIT 1`,
    [orderId],
  );

  const order = orderRows[0];
  if (!order) {
    throw new Error(`Order not found for invoice: ${orderId}`);
  }

  const paymentEvents = (await pool.query<OrderPaymentEventRow[]>(
    `SELECT * FROM order_payment_events
     WHERE order_id = ?
     ORDER BY event_time ASC`,
    [orderId],
  ))[0];

  const lateFeeEvents = (await pool.query<OrderLateFeeEventRow[]>(
    `SELECT * FROM order_late_fee_events
     WHERE order_id = ?
     ORDER BY fee_date ASC`,
    [orderId],
  ))[0];

  const totalAmount = Number(order.total_amount ?? 0);
  const downpaymentAmount = Number(order.downpayment_amount ?? 0);
  const remainingBalance = Number(order.remaining_balance ?? 0);
  const paymentStatus = (order.payment_status ?? '').toString().toLowerCase();

  const depositPaid = paymentEvents.reduce((sum, p) => {
    if (p.event_type === 'downpayment') return sum + Number(p.amount);
    return sum;
  }, 0);

  const paidSum = paymentEvents.reduce((sum, p) => sum + Number(p.amount), 0);
  const totalLateFees = lateFeeEvents.reduce((sum, f) => sum + Number(f.amount), 0);
  const [itemRows] = await pool.query<RowDataPacket[]>(
    `SELECT product_name, quantity, line_total
     FROM order_items
     WHERE order_id = ?
     ORDER BY id ASC`,
    [orderId],
  );
  const lineItems: InvoiceLineItem[] = itemRows.map((r) => ({
    description: `${String(r.product_name ?? 'Item')} x${Number(r.quantity ?? 1)}`,
    amount: Number(r.line_total ?? 0),
  }));

  // Remaining balance is the authoritative amount customers still owe.
  const totalBalanceDue = remainingBalance > 0 ? remainingBalance : 0;

  const isPaid = paymentStatus === 'completed' || totalBalanceDue <= 0.01;

  const version: InvoiceVersion = isPaid
    ? 'paid_final'
    : lateFeeEvents.length > 0
      ? 'progress_version'
      : paymentEvents.length <= 1
        ? 'deposit_version'
        : 'progress_version';

  const invoiceTitle =
    version === 'paid_final'
      ? 'Your Paid Invoice'
      : version === 'deposit_version'
        ? 'Your Deposit Invoice'
        : 'Your Updated Invoice';

  const subject = `Updated Invoice for Order #${shortOrderId(orderId)}`;

  const bodyHtml = buildInvoiceBodyHtml({
    version,
    orderId,
    invoiceTitle,
    customerName: String(order.contact_name ?? 'Customer'),
    line1: String(order.shipping_line1 ?? ''),
    city: String(order.shipping_region ?? ''),
    invoiceDate: order.created_at instanceof Date ? order.created_at : new Date(order.created_at),
    customerId: String(order.user_id ?? ''),
    totalPrice: totalAmount,
    depositPaid: depositPaid > 0 ? depositPaid : downpaymentAmount,
    totalBalanceDue,
    totalLateFees,
    lineItems,
    paymentEvents,
    lateFeeEvents,
  });

  return {
    version,
    invoiceNumber: orderId,
    invoiceTitle,
    subject,
    bodyHtml,
    depositPaid: depositPaid > 0 ? depositPaid : downpaymentAmount,
    totalBalanceDue,
    totalLateFees,
    paymentEvents,
    lateFeeEvents,
  };
};

