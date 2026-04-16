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
  readonly totalPrice: number;
  readonly depositPaid: number;
  readonly totalBalanceDue: number;
  readonly totalLateFees: number;
  readonly paymentEvents: OrderPaymentEventRow[];
  readonly lateFeeEvents: OrderLateFeeEventRow[];
}): string => {
  const {
    version,
    orderId,
    invoiceTitle,
    totalPrice,
    depositPaid,
    totalBalanceDue,
    totalLateFees,
    paymentEvents,
    lateFeeEvents,
  } = params;
  const invoiceNumber = orderId;

  const paymentRowsHtml =
    paymentEvents.length === 0
      ? `<tr><td colspan="3" style="padding:10px 8px;color:#6b7280;">No payments recorded.</td></tr>`
      : paymentEvents
          .map(
            (p) => `
          <tr>
            <td style="padding:8px;color:#374151;">${escapeHtml(p.event_time.toISOString().slice(0, 10))}</td>
            <td style="padding:8px;color:#374151;">${escapeHtml(p.event_type.replace(/_/g, ' '))}</td>
            <td style="padding:8px;text-align:right;color:#111827;font-weight:600;">${escapeHtml(formatPesos(Number(p.amount)))}</td>
          </tr>`,
          )
          .join('');

  const lateFeeRowsHtml =
    lateFeeEvents.length === 0
      ? `<tr><td colspan="2" style="padding:10px 8px;color:#6b7280;">No late fees applied yet.</td></tr>`
      : lateFeeEvents
          .map((f) => {
            const d = f.fee_date.toISOString().slice(0, 10);
            return `
              <tr>
                <td style="padding:8px;color:#374151;">${escapeHtml(d)}</td>
                <td style="padding:8px;text-align:right;color:#111827;font-weight:600;">${escapeHtml(formatPesos(Number(f.amount)))}</td>
              </tr>`;
          })
          .join('');

  const paidStamp =
    version === 'paid_final'
      ? `<div style="position:absolute;top:18px;right:18px;background:#16a34a;color:#fff;padding:10px 14px;border-radius:14px;transform:rotate(8deg);font-weight:800;letter-spacing:1px;font-size:22px;">
            PAID
          </div>`
      : '';

  const versionBadge =
    version === 'deposit_version'
      ? `Deposit Version (Initial)`
      : version === 'paid_final'
        ? 'Paid Version (Final)'
        : 'Progress Version (Middle)';

  return `
      <div style="position:relative;">
        ${paidStamp}
        <div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:14px;padding:14px;margin-bottom:14px;">
          <div style="display:flex;gap:12px;flex-wrap:wrap;">
            <div style="flex:1;min-width:220px;">
              <div style="font-size:12px;color:#6b7280;font-weight:700;letter-spacing:.02em;">Total Price</div>
              <div style="font-size:20px;font-weight:900;color:#111827;margin-top:6px;">${escapeHtml(formatPesos(totalPrice))}</div>
            </div>
            <div style="flex:1;min-width:220px;">
              <div style="font-size:12px;color:#6b7280;font-weight:700;letter-spacing:.02em;">Deposit Paid</div>
              <div style="font-size:20px;font-weight:800;color:#7b5a4f;margin-top:6px;">${escapeHtml(formatPesos(depositPaid))}</div>
            </div>
            <div style="flex:1;min-width:220px;">
              <div style="font-size:12px;color:#6b7280;font-weight:700;letter-spacing:.02em;">Total Late Fees</div>
              <div style="font-size:20px;font-weight:800;color:#7b5a4f;margin-top:6px;">${escapeHtml(formatPesos(totalLateFees))}</div>
            </div>
          </div>
        </div>

        <div style="background:#fff;border:1px solid #e5e7eb;border-radius:14px;overflow:hidden;">
          <div style="padding:12px 14px;background:#111827;color:#fff;font-weight:800;">Invoice Summary</div>
          <div style="padding:14px;">
            <div style="display:flex;align-items:flex-end;justify-content:space-between;gap:12px;flex-wrap:wrap;">
              <div>
                <div style="font-size:12px;color:#6b7280;font-weight:700;letter-spacing:.02em;">Total Balance Due</div>
                <div style="font-size:34px;font-weight:900;color:#111827;margin-top:6px;">${escapeHtml(formatPesos(totalBalanceDue))}</div>
                <div style="font-size:12px;color:#6b7280;margin-top:4px;">This amount updates automatically after each payment and late-fee charge.</div>
              </div>
              <div style="min-width:260px;max-width:320px;">
                <div style="font-size:12px;color:#6b7280;font-weight:700;letter-spacing:.02em;">What’s included</div>
                <div style="margin-top:8px;font-size:14px;color:#374151;line-height:1.5;">
                  <div>• All payments made</div>
                  <div>• Every ₱100/day late-fee charge after the 3-month window</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div style="height:12px;"></div>

        <div style="background:#fff;border:1px solid #e5e7eb;border-radius:14px;overflow:hidden;margin-bottom:14px;">
          <div style="padding:12px 14px;background:#f3f4f6;color:#111827;font-weight:800;">Payments</div>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
            <thead>
              <tr>
                <th align="left" style="padding:8px;color:#6b7280;font-size:12px;font-weight:700;border-top:1px solid #e5e7eb;">Date</th>
                <th align="left" style="padding:8px;color:#6b7280;font-size:12px;font-weight:700;border-top:1px solid #e5e7eb;">Type</th>
                <th align="right" style="padding:8px;color:#6b7280;font-size:12px;font-weight:700;border-top:1px solid #e5e7eb;">Amount</th>
              </tr>
            </thead>
            <tbody>
              ${paymentRowsHtml}
            </tbody>
          </table>
        </div>

        <div style="background:#fff;border:1px solid #e5e7eb;border-radius:14px;overflow:hidden;">
          <div style="padding:12px 14px;background:#f3f4f6;color:#111827;font-weight:800;">Late Fees (₱100/day)</div>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
            <thead>
              <tr>
                <th align="left" style="padding:8px;color:#6b7280;font-size:12px;font-weight:700;border-top:1px solid #e5e7eb;">Date</th>
                <th align="right" style="padding:8px;color:#6b7280;font-size:12px;font-weight:700;border-top:1px solid #e5e7eb;">Amount</th>
              </tr>
            </thead>
            <tbody>
              ${lateFeeRowsHtml}
            </tbody>
          </table>
        </div>

        <div style="height:18px;"></div>
        <div style="background:#111827;border-radius:18px;padding:18px;position:relative;overflow:hidden;">
          <div style="font-size:12px;color:#cbd5e1;font-weight:800;letter-spacing:.12em;text-transform:uppercase;">Balance Due</div>
          <div style="font-size:38px;font-weight:900;color:#fff;margin-top:8px;letter-spacing:.01em;">${escapeHtml(formatPesos(totalBalanceDue))}</div>
          <div style="font-size:12px;color:#cbd5e1;margin-top:6px;line-height:1.4;">This invoice updates automatically as payments and daily late fees are recorded.</div>
        </div>

        <div style="margin-top:14px;background:#F0EEF9;border-radius:14px;padding:14px;color:#4B5563;font-size:12px;line-height:1.4;">
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
      payment_plan
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
    totalPrice: totalAmount,
    depositPaid: depositPaid > 0 ? depositPaid : downpaymentAmount,
    totalBalanceDue,
    totalLateFees,
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

