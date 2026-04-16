import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { updateOrderStatus } from '../services/order_service';
import { EmailService } from '../services/email_service';
import { logAdminActivity } from '../services/admin_activity_log_service';

const escapeOrderIdForLog = (orderId: string): string => orderId.substring(0, 8).toUpperCase();

let _schemaEnsured = false;

const ensureInstallmentPolicySchema = async (): Promise<void> => {
  if (_schemaEnsured) return;
  const pool = getPool();

  // Ledger tables (invoice uses them).
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

  // Order columns to support idempotent accrual + warnings + default cancellation.
  const safeAddColumn = async (sql: string): Promise<void> => {
    try {
      await pool.query(sql);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      // Duplicate column is safe to ignore.
      if (msg.includes('Duplicate column') || msg.toLowerCase().includes('duplicate column name')) return;
      // Unknown column might happen on ALTER TABLE enum changes; surface it.
      throw e;
    }
  };

  await safeAddColumn(
    `ALTER TABLE orders ADD COLUMN cancellation_reason VARCHAR(120) NULL DEFAULT NULL`,
  );
  await safeAddColumn(
    `ALTER TABLE orders ADD COLUMN payment_default_cancelled_at TIMESTAMP NULL DEFAULT NULL`,
  );
  await safeAddColumn(
    `ALTER TABLE orders ADD COLUMN late_fee_accrued_days INT NOT NULL DEFAULT 0`,
  );
  await safeAddColumn(
    `ALTER TABLE orders ADD COLUMN late_fee_last_email_sent_on DATE NULL DEFAULT NULL`,
  );
  await safeAddColumn(
    `ALTER TABLE orders ADD COLUMN payment_default_warn_2m_sent_at TIMESTAMP NULL DEFAULT NULL`,
  );
  await safeAddColumn(
    `ALTER TABLE orders ADD COLUMN payment_default_warn_80d_sent_at TIMESTAMP NULL DEFAULT NULL`,
  );
  await safeAddColumn(
    `ALTER TABLE orders ADD COLUMN payment_default_warn_90d_sent_at TIMESTAMP NULL DEFAULT NULL`,
  );

  _schemaEnsured = true;
};

const parseIsoDateOnly = (d: Date): string => d.toISOString().slice(0, 10);

const startOfDayUtc = (d: Date): Date => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0, 0));

const daysBetweenUtc = (a: Date, b: Date): number => {
  const ms = b.getTime() - a.getTime();
  return Math.max(0, Math.floor(ms / (24 * 60 * 60 * 1000)));
};

/**
 * Accrues late fees (₱100/day) for PayMongo downpayment orders:
 * - Charges start after the 3-month window ends
 * - Cancel after 6 months (payment default; deposit forfeited)
 * - Sends 2/80/90-day warning emails
 */
export const runInstallmentPolicyJob = async (): Promise<void> => {
  const pool = getPool();
  await ensureInstallmentPolicySchema();

  const now = new Date();
  const todayDateStr = parseIsoDateOnly(now);

  // Query candidate orders once per run.
  const [rows] = await pool.query<
    (RowDataPacket & {
      id: string;
      user_id: string;
      downpayment_amount: number;
      remaining_balance: number;
      payment_status: string;
      first_installment_paid_at: Date | string | null;
      late_fee_accrued_days: number;
      late_fee_last_email_sent_on: Date | string | null;
      cancellation_reason: string | null;
      payment_default_cancelled_at: Date | string | null;
      payment_default_warn_2m_sent_at: Date | string | null;
      payment_default_warn_80d_sent_at: Date | string | null;
      payment_default_warn_90d_sent_at: Date | string | null;
    })[]
  >(
    `
    SELECT 
      id,
      user_id,
      downpayment_amount,
      remaining_balance,
      payment_status,
      first_installment_paid_at,
      late_fee_accrued_days,
      late_fee_last_email_sent_on,
      cancellation_reason,
      payment_default_cancelled_at,
      payment_default_warn_2m_sent_at,
      payment_default_warn_80d_sent_at,
      payment_default_warn_90d_sent_at
    FROM orders
    WHERE payment_method = 'paymongo'
      AND payment_plan = 'downpayment'
      AND payment_status <> 'completed'
      AND status <> 'cancelled'
      AND first_installment_paid_at IS NOT NULL
      AND remaining_balance > 0.01
    `,
  );

  const feePerDay = 100;
  const resultsToCancel: string[] = [];

  // First pass: accrue late fees and schedule warnings.
  for (const row of rows) {
    const orderId = row.id as string;
    const userId = row.user_id as string;

    const firstInstallment = row.first_installment_paid_at instanceof Date ? row.first_installment_paid_at : new Date(row.first_installment_paid_at as string);
    if (isNaN(firstInstallment.getTime())) continue;

    const remainingBalanceInitial = Number(row.remaining_balance ?? 0);
    let remainingBalance = remainingBalanceInitial;

    const zeroInterestEndsAt = new Date(
      firstInstallment.getFullYear(),
      firstInstallment.getMonth() + 3,
      firstInstallment.getDate(),
      firstInstallment.getHours(),
      firstInstallment.getMinutes(),
      firstInstallment.getSeconds(),
      firstInstallment.getMilliseconds(),
    );

    // Late fees start from the day after `zeroInterestEndsAt`'s calendar boundary.
    const lateFeeStartUtc = startOfDayUtc(zeroInterestEndsAt);
    const nowUtc = startOfDayUtc(now);

    const accruedDays = Number(row.late_fee_accrued_days ?? 0);
    const dayDiffFromStart = daysBetweenUtc(lateFeeStartUtc, nowUtc);

    // Daily late fee accrual.
    if (dayDiffFromStart > accruedDays) {
      const newDays = dayDiffFromStart - accruedDays;
      const newTotalFee = newDays * feePerDay;
      remainingBalance = remainingBalance + newTotalFee;

      const lateFeeLastEmail = row.late_fee_last_email_sent_on;
      const lastEmailDateStr = typeof lateFeeLastEmail === 'string' ? lateFeeLastEmail : lateFeeLastEmail ? parseIsoDateOnly(lateFeeLastEmail as Date) : null;

      // Accrue + insert ledger in a transaction.
      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();

        // Update remaining balance.
        await conn.query(
          `UPDATE orders 
           SET remaining_balance = remaining_balance + ?, 
               late_fee_accrued_days = ?, 
               updated_at = NOW()
           WHERE id = ?`,
          [newTotalFee, dayDiffFromStart, orderId],
        );

        // Insert one ledger row per day (idempotent via UNIQUE(order_id, fee_date)).
        for (let i = accruedDays; i < dayDiffFromStart; i++) {
          const feeDate = new Date(lateFeeStartUtc.getTime() + i * 24 * 60 * 60 * 1000);
          const feeDateStr = parseIsoDateOnly(feeDate);

          await conn.query(
            `INSERT INTO order_late_fee_events (id, order_id, fee_date, amount)
             VALUES (?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE amount = amount`,
            [`lfe_${orderId.substring(0, 8)}_${feeDateStr}`, orderId, feeDateStr, feePerDay],
          );
        }

        await conn.commit();
      } catch (e) {
        await conn.rollback();
        console.error(`❌ Late-fee accrual failed for order ${orderId}:`, e);
      } finally {
        conn.release();
      }

      // Email invoice update at most once per calendar day per order.
      if (lastEmailDateStr !== todayDateStr) {
        try {
          await EmailService.sendUpdatedInvoiceEmail({ userId, orderId });
          await pool.query(
            `UPDATE orders SET late_fee_last_email_sent_on = ?, updated_at = NOW() WHERE id = ?`,
            [todayDateStr, orderId],
          );
        } catch (e) {
          console.error(`❌ Failed to send late-fee invoice update email for ${orderId}:`, e);
        }
      }
    }

    // Payment default warnings and cancellation.
    const paymentDeadlineAt = new Date(
      firstInstallment.getFullYear(),
      firstInstallment.getMonth() + 6,
      firstInstallment.getDate(),
      firstInstallment.getHours(),
      firstInstallment.getMinutes(),
      firstInstallment.getSeconds(),
      firstInstallment.getMilliseconds(),
    );

    const warn2mAt = new Date(
      firstInstallment.getFullYear(),
      firstInstallment.getMonth() + 2,
      firstInstallment.getDate(),
      firstInstallment.getHours(),
      firstInstallment.getMinutes(),
      firstInstallment.getSeconds(),
      firstInstallment.getMilliseconds(),
    );
    const warn80dAt = new Date(firstInstallment.getTime() + 80 * 24 * 60 * 60 * 1000);
    const warn90dAt = new Date(firstInstallment.getTime() + 90 * 24 * 60 * 60 * 1000);

    const shouldSend2m = !row.payment_default_warn_2m_sent_at && now >= warn2mAt;
    const shouldSend80d = !row.payment_default_warn_80d_sent_at && now >= warn80dAt;
    const shouldSend90d = !row.payment_default_warn_90d_sent_at && now >= warn90dAt;

    const depositAmount = Number(row.downpayment_amount ?? 0);

    if (shouldSend2m) {
      await EmailService.sendPaymentDefaultWarningEmail({
        userId,
        orderId,
        payByAt: paymentDeadlineAt,
        depositAmount,
        remainingBalance,
      });
      await pool.query(
        `UPDATE orders SET payment_default_warn_2m_sent_at = NOW(), updated_at = NOW() WHERE id = ?`,
        [orderId],
      );
    }
    if (shouldSend80d) {
      await EmailService.sendPaymentDefaultWarningEmail({
        userId,
        orderId,
        payByAt: paymentDeadlineAt,
        depositAmount,
        remainingBalance,
      });
      await pool.query(
        `UPDATE orders SET payment_default_warn_80d_sent_at = NOW(), updated_at = NOW() WHERE id = ?`,
        [orderId],
      );
    }
    if (shouldSend90d) {
      await EmailService.sendPaymentDefaultWarningEmail({
        userId,
        orderId,
        payByAt: paymentDeadlineAt,
        depositAmount,
        remainingBalance,
      });
      await pool.query(
        `UPDATE orders SET payment_default_warn_90d_sent_at = NOW(), updated_at = NOW() WHERE id = ?`,
        [orderId],
      );
    }

    // Cancel at the 6-month default deadline if balance still owed.
    const isOverdue = now >= paymentDeadlineAt;
    const alreadyCancelled = Boolean(row.payment_default_cancelled_at) || row.cancellation_reason === 'payment_default_non_payment_6_months';
    if (isOverdue && !alreadyCancelled) {
      resultsToCancel.push(orderId);
    }
  }

  // Cancellation pass (keeps restore inventory + cancellation email in one place).
  for (const orderId of resultsToCancel) {
    try {
      const [orderRows] = await pool.query<any[]>(
        `SELECT id, user_id, downpayment_amount FROM orders WHERE id = ? LIMIT 1`,
        [orderId],
      );
      const order = orderRows[0];
      if (!order) continue;

      // Mark reason + timing first so updateOrderStatus can send the correct email.
      await pool.query(
        `UPDATE orders
         SET cancellation_reason = 'payment_default_non_payment_6_months',
             payment_default_cancelled_at = NOW(),
             payment_status = 'failed',
             updated_at = NOW()
         WHERE id = ?`,
        [orderId],
      );

      await updateOrderStatus(orderId, 'cancelled');

      await logAdminActivity({
        adminId: null,
        action: 'payment_default_cancelled',
        entityType: 'order',
        entityId: orderId,
        details: {
          reason: 'non-payment after 6 months',
          downpaymentAmount: String(Number(order.downpayment_amount ?? 0)),
        },
      });
    } catch (e) {
      console.error(`❌ Payment-default cancellation failed for ${orderId}:`, e);
    }
  }
};

export const startInstallmentPolicyScheduler = (): void => {
  try {
    const cron = require('node-cron');
    // Run frequently enough to reliably hit the warning windows.
    cron.schedule('*/10 * * * *', async () => {
      try {
        await runInstallmentPolicyJob();
      } catch (e) {
        console.error('Installment policy job failed:', e);
      }
    });
    console.log('✅ Installment policy scheduler started (late fees + 6-month default)');
  } catch (error) {
    console.warn('⚠️ node-cron not installed. Installment policy scheduler not started.');
    console.warn('   Install with: npm install node-cron');
  }
};

