import nodemailer from 'nodemailer';
import { RowDataPacket } from 'mysql2';
import sgMail from '@sendgrid/mail';
import { Resend } from 'resend';
import { config } from '../config/env';
import { getPool } from '../config/database';
import { buildUpdatedOrderInvoiceHtml } from './order_invoice_service';

type UserRow = RowDataPacket & {
  readonly email: string;
  readonly full_name: string;
};

type AdminEmailRow = RowDataPacket & {
  readonly email: string;
  readonly full_name: string | null;
};

/** Avoid breaking HTML email bodies when names contain <>&. */
const escapeHtml = (value: string): string =>
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

/** Only allow http(s) image URLs in HTML `src` (prevents javascript: etc.). */
const safeEmailImageUrl = (raw: string): string => {
  const t = raw.trim();
  if (!t) return '';
  try {
    const u = new URL(t);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return '';
    return u.toString();
  } catch {
    return '';
  }
};

/**
 * Email service for sending order confirmation emails.
 * In production, integrate with a service like SendGrid, AWS SES, or Nodemailer.
 */
const buildTransporter = (): nodemailer.Transporter | null => {
  // Guard clause ensures we only attempt to send email when the critical Gmail
  // credentials have been provided. Missing values would otherwise produce
  // confusing runtime errors, so we fail fast with a clear warning instead.
  if (!config.email.username || !config.email.password) {
    console.warn(
      '⚠️  SMTP credentials missing (set SMTP_USER/SMTP_PASS or SMTP_USERNAME/SMTP_PASSWORD). Email notifications are disabled.',
    );
    return null;
  }

  // Nodemailer reuses the transporter under the hood, so we can create it once
  // and keep returning the same instance to avoid recreating sockets on every
  // single email send operation.
  return nodemailer.createTransport({
    host: config.email.host,
    port: config.email.port,
    secure: config.email.secure,
    auth: {
      user: config.email.username,
      pass: config.email.password,
    },
  });
};

let cachedTransporter: nodemailer.Transporter | null = null;
let cachedResend: Resend | null = null;
let sendGridInitialized = false;

type EmailPayload = {
  readonly to: string | string[];
  readonly subject: string;
  readonly html: string;
  readonly text?: string;
};

const ensureSendGrid = (): boolean => {
  if (sendGridInitialized) return Boolean(config.sendgrid.apiKey);
  sendGridInitialized = true;
  if (!config.sendgrid.apiKey) return false;

  try {
    sgMail.setApiKey(config.sendgrid.apiKey);
    return true;
  } catch (error) {
    console.error('❌ Failed to initialize SendGrid client:', error);
    return false;
  }
};

/**
 * Resend requires the `from` email's domain to be verified in the Resend
 * dashboard. If you're using Gmail but haven't verified a custom domain
 * yet (common on Render Free), we can safely use Resend's pre-verified
 * sender domain instead.
 *
 * We preserve the display name from `config.email.from` so the email still
 * looks like it's coming from your brand.
 */
const getResendFrom = (): string => {
  const from = config.email.from ?? 'Wood Home Furniture Trading';
  const displayName = (() => {
    const match = from.match(/^(.*)<.*>$/);
    if (match?.[1]) return match[1].trim().replace(/(^"|"$)/g, '');
    return from.trim();
  })();

  return `${displayName} <onboarding@resend.dev>`;
};

const getResendReplyTo = (): string => {
  // Keep reply-to on a verified Resend domain to avoid additional
  // domain verification errors when you haven't added a custom domain yet.
  return 'onboarding@resend.dev';
};

/**
 * Lazily initializes the Resend client.
 *
 * Why lazy init?
 * - Render Free services often start with no email creds until env is set.
 * - It also keeps startup fast when email is not needed.
 */
const getResendClient = (): Resend | null => {
  if (cachedResend != null) return cachedResend;
  if (!config.resend.apiKey) return null;

  try {
    cachedResend = new Resend(config.resend.apiKey);
    return cachedResend;
  } catch (error) {
    console.error('❌ Failed to initialize Resend client:', error);
    cachedResend = null;
    return null;
  }
};

type ParsedSender = {
  readonly name?: string;
  readonly email: string;
};

const parseSenderFromField = (from: string): ParsedSender => {
  const trimmed = from.trim();
  // Expected format: "Display Name <sender@email.com>"
  const match = trimmed.match(/^(.*)<([^>]+)>$/);
  if (match) {
    const name = match[1].trim();
    const email = match[2].trim();
    return { name: name.length > 0 ? name : undefined, email };
  }
  return { email: trimmed };
};

const sendViaBrevo = async (payload: EmailPayload): Promise<void> => {
  const apiKey = config.brevo.apiKey;
  if (!apiKey) return;

  const sender = parseSenderFromField(config.brevo.from);
  const toList = Array.isArray(payload.to) ? payload.to : [payload.to];

  // Brevo transactional email API (no SMTP egress required)
  // https://developers.brevo.com/docs/smtp-v3/
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      sender: {
        ...(sender.name ? { name: sender.name } : {}),
        email: sender.email,
      },
      to: toList.map((email) => ({ email })),
      subject: payload.subject,
      htmlContent: payload.html,
      textContent: payload.text ?? '',
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Brevo send failed (${res.status}): ${body}`);
  }
};

const sendEmail = async (payload: EmailPayload): Promise<void> => {
  // Prefer Brevo when configured. Brevo uses HTTPS API so it works on free
  // Render plans where SMTP egress may be blocked.
  if (config.brevo.apiKey) {
    try {
      await sendViaBrevo(payload);
      return;
    } catch (e) {
      console.error('❌ Brevo send failed, falling back:', e);
    }
  }

  // Fallback to SendGrid when configured.
  if (ensureSendGrid()) {
    await sgMail.send({
      to: payload.to,
      from: config.sendgrid.from,
      subject: payload.subject,
      html: payload.html,
      text: payload.text,
      replyTo: config.sendgrid.from,
    });
    return;
  }

  // Resend fallback (kept for flexibility). Note: `resend.dev` is restricted.
  const resend = getResendClient();
  if (resend == null) {
    console.warn('⚠️ Email delivery disabled: configure Brevo, SendGrid, or Resend.');
    return;
  }

  await resend.emails.send({
    from: getResendFrom(),
    to: payload.to,
    subject: payload.subject,
    html: payload.html,
    text: payload.text ?? '',
    reply_to: getResendReplyTo(),
  });
};

type WoodHomeTemplateInput = {
  readonly heading: string;
  readonly greeting: string;
  /**
   * Optional HTML version of [greeting], for cases like bolding the name.
   * Callers must pass safe, pre-escaped HTML.
   */
  readonly greetingHtml?: string;
  readonly intro: string;
  readonly bodyHtml: string;
  readonly footerNote?: string;
};

/**
 * Shared email shell matching the original Wood Home verification layout.
 * This keeps all customer emails visually consistent.
 */
const buildWoodHomeTemplate = (input: WoodHomeTemplateInput): string => {
  const logoSrc = safeEmailImageUrl(config.emailBranding.logoUrl);
  const greetingBlock = (() => {
    if (input.greetingHtml) return input.greetingHtml;

    // Auto-bold common greeting pattern:
    // - "Hi Admin,"
    // - "Hi John Doe,"
    const match = input.greeting.match(/^Hi\s+(.+),\s*$/i);
    if (match?.[1]) {
      return `Hi <strong>${escapeHtml(match[1])}</strong>,`;
    }

    // Fallback: plain text greeting
    return escapeHtml(input.greeting);
  })();

  const fbHref = escapeHtml(config.brand.facebookUrl);
  const iconSrc = safeEmailImageUrl(config.brand.facebookIconUrl);
  const fbIcon = iconSrc
    ? `<img src="${escapeHtml(iconSrc)}" alt="Facebook" width="20" height="20" style="display:inline-block;vertical-align:middle;border:0;margin-right:6px;" />`
    : `<span style="display:inline-block;width:20px;height:20px;line-height:20px;text-align:center;background:#1877F2;border-radius:50%;color:#fff;font-weight:700;font-size:13px;margin-right:6px;vertical-align:middle;">f</span>`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap" rel="stylesheet">
  <title>${escapeHtml(input.heading)}</title>
</head>
<body style="margin:0;padding:14px;background:#f3f3f3;font-family:Poppins,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;color:#2a2a2a;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#ffffff;border:1px solid #dedede;border-radius:8px;overflow:hidden;">
          <tr>
            <td style="padding:28px;background:#5C4033;text-align:center;">
              ${logoSrc ? `<img src="${escapeHtml(logoSrc)}" alt="Wood Home Furniture Trading" width="96" style="display:block;margin:0 auto 12px;max-width:110px;height:auto;border:0;" />` : ''}
              <p style="margin:0;color:#fff;font-size:30px;line-height:1.15;font-weight:700;letter-spacing:0.2px;">${escapeHtml(input.heading)}</p>
            </td>
          </tr>
          <tr>
            <td style="padding:22px 18px 10px;">
              <p style="margin:0 0 14px;font-size:22px;color:#2f2f2f;">${greetingBlock}</p>
              <p style="margin:0 0 18px;font-size:22px;line-height:1.35;color:#2f2f2f;">${escapeHtml(input.intro)}</p>
              ${input.bodyHtml}
              ${
                input.footerNote
                  ? `<p style="margin:18px 0 0;font-size:18px;line-height:1.4;color:#444;">${escapeHtml(input.footerNote)}</p>`
                  : ''
              }
            </td>
          </tr>
          <tr>
            <td style="padding:12px 18px 18px;border-top:1px solid #ededed;text-align:center;">
              <a href="${fbHref}" style="display:inline-flex;align-items:center;gap:6px;text-decoration:none;color:#1877F2;font-size:16px;font-weight:600;">
                ${fbIcon}
              </a>
              <p style="margin:10px 0 0;font-size:13px;color:#999;">Wood Home Furniture Trading</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
};

export class EmailService {
  /**
   * Sends one admin-facing event email (to all admin recipients).
   * Used for operational alerts like cancelled orders and new support messages.
   */
  static async sendAdminEventEmail(params: {
    readonly title: string;
    readonly message: string;
    readonly details?: ReadonlyArray<{ readonly label: string; readonly value: string }>;
  }): Promise<void> {
    try {
      const recipients = await EmailService.getAdminRecipients();
      if (recipients.length === 0) {
        return;
      }
      const detailRows = (params.details ?? [])
        .map(
          (d) =>
            `<tr><td style="padding:6px 0;color:#6b7280;">${escapeHtml(d.label)}</td><td style="padding:6px 0;font-weight:600;">${escapeHtml(d.value)}</td></tr>`,
        )
        .join('');
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Admin Activity Alert',
        greeting: 'Hi Admin,',
        intro: params.message,
        bodyHtml:
          detailRows.length > 0
            ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">${detailRows}</table>`
            : `<p style="margin:0;font-size:18px;color:#444;">No additional details.</p>`,
        footerNote: 'SmartSpace admin alert',
      });
      await sendEmail({
        to: recipients.map((r) => r.email),
        subject: `[Admin Alert] ${params.title}`,
        html: htmlBody,
        text: `${params.title}\n\n${params.message}`,
      });
    } catch (error) {
      console.error('❌ Failed to send admin event email:', error);
    }
  }

  /**
   * Pull active admin recipients from the admins table.
   */
  static async getAdminRecipients(): Promise<ReadonlyArray<{ readonly email: string; readonly name: string }>> {
    const pool = getPool();
    const [rows] = await pool.query<AdminEmailRow[]>(
      `SELECT email, full_name FROM admins WHERE COALESCE(is_active, TRUE) = TRUE`,
    );
    return rows
      .map((row) => ({
        email: String(row.email ?? '').trim(),
        name: String(row.full_name ?? '').trim(),
      }))
      .filter((row) => row.email.length > 0);
  }

  /**
   * Sends an order expiration email when the order is marked as expired.
   * Used when admin expires an order or when the system auto-expires unpaid orders.
   */
  static async sendOrderExpiredEmail(userId: string, orderId: string): Promise<void> {
    try {
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );

      if (rows.length === 0) {
        console.warn(`⚠️ User ${userId} not found, cannot send expired-order email`);
        return;
      }

      const user = rows[0];
      const email = user.email;
      const userName = user.full_name;

      const shortId = orderId.substring(0, 8).toUpperCase();
      const subject = `Order expired — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Order Update',
        greeting: `Hi ${userName},`,
        intro: 'Your order is no longer active.',
        bodyHtml: `<p style="margin:0;font-size:20px;line-height:1.45;color:#333;">Order <strong>#${escapeHtml(shortId)}</strong> has expired. You can place a new order any time in the app.</p>`,
      });
      await sendEmail({
        to: email,
        subject,
        html: htmlBody,
        text: `Order #${shortId} expired.`,
      });

      console.log(`📧 Sent expired-order notice to ${email} for order ${orderId}`);
    } catch (error) {
      console.error('❌ Failed to send expired-order email:', error);
      // Do not throw; email failure should not break order updates
    }
  }

  /**
   * Gentle nudge when PayMongo checkout was opened but payment is still pending
   * (inventory is held until the order is paid or auto-cancelled).
   */
  static async sendPendingPaymentReminderEmail(
    userId: string,
    orderId: string,
    orderTotal: number,
  ): Promise<void> {
    try {
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );
      if (rows.length === 0) {
        console.warn(`⚠️ User ${userId} not found, cannot send payment reminder`);
        return;
      }
      const user = rows[0];
      const shortId = orderId.substring(0, 8).toUpperCase();
      const totalStr = orderTotal.toFixed(2);
      const subject = `Payment pending — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Payment Reminder',
        greeting: `Hi ${user.full_name},`,
        intro: `Order #${shortId} is waiting for payment.`,
        bodyHtml: `<p style="margin:0 0 10px;font-size:20px;line-height:1.4;color:#333;">Total amount: <strong>₱${escapeHtml(totalStr)}</strong></p>
<p style="margin:0;font-size:18px;line-height:1.45;color:#333;">Please complete payment in the app under <strong>Orders</strong> to avoid auto-cancellation.</p>`,
      });
      await sendEmail({
        to: user.email,
        subject,
        html: htmlBody,
        text: `Order #${shortId} — ₱${totalStr}. Complete payment in the app (Orders).`,
      });
      console.log(`📧 Sent payment reminder to ${user.email} for ${orderId}`);
    } catch (error) {
      console.error('❌ Failed to send payment reminder email:', error);
    }
  }

  /**
   * Sends an order confirmation email to the user.
   * Currently logs to console - replace with actual email service in production.
   */
  static async sendOrderConfirmationEmail(
    userId: string,
    orderId: string,
    orderTotal: number,
  ): Promise<void> {
    try {
      // Fetch user email from database
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );

      if (rows.length === 0) {
        console.warn(`⚠️ User ${userId} not found, cannot send email`);
        return;
      }

      const user = rows[0];
      const email = user.email;
      const userName = user.full_name;

      const shortId = orderId.substring(0, 8).toUpperCase();
      const subject = `Order confirmed — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Order Confirmed',
        greeting: `Hi ${userName},`,
        intro: 'Great news! Your order has been confirmed.',
        bodyHtml: `<p style="margin:0 0 10px;font-size:20px;line-height:1.4;color:#333;">Order number: <strong>#${escapeHtml(shortId)}</strong></p>
<p style="margin:0;font-size:20px;line-height:1.4;color:#333;">Total: <strong>₱${escapeHtml(orderTotal.toFixed(2))}</strong></p>`,
      });
      await sendEmail({
        to: email,
        subject,
        html: htmlBody,
        text: `Order #${shortId} confirmed. Total ₱${orderTotal.toFixed(2)}.`,
      });

      // Keep a slim log trail so we can trace successful sends without dumping
      // the entire email body, which could contain sensitive information.
      console.log(`📧 Sent order confirmation to ${email} for order ${orderId}`);
    } catch (error) {
      console.error('❌ Failed to send order confirmation email:', error);
      // Don't throw - email failure shouldn't break order confirmation
    }
  }

  /**
   * Sends a payment confirmation email to the user after admin verifies payment proof.
   */
  static async sendPaymentConfirmationEmail(
    userId: string,
    orderId: string,
    orderTotal: number,
    paymentMethod: string,
  ): Promise<void> {
    try {
      // Fetch user email from database
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );

      if (rows.length === 0) {
        console.warn(`⚠️ User ${userId} not found, cannot send email`);
        return;
      }

      const user = rows[0];
      const email = user.email;
      const userName = user.full_name;

      const isCOD = paymentMethod === 'cod';
      const shortId = orderId.substring(0, 8).toUpperCase();
      const subject = `Payment received — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Payment Confirmed',
        greeting: `Hi ${userName},`,
        intro: 'We received your payment successfully.',
        bodyHtml: `<p style="margin:0 0 10px;font-size:20px;line-height:1.4;color:#333;">Order number: <strong>#${escapeHtml(shortId)}</strong></p>
<p style="margin:0 0 10px;font-size:20px;line-height:1.4;color:#333;">Amount: <strong>₱${escapeHtml(orderTotal.toFixed(2))}</strong></p>
${isCOD ? `<p style="margin:0;font-size:18px;line-height:1.45;color:#333;">Remaining balance will be collected on delivery.</p>` : ''}`,
      });
      await sendEmail({
        to: email,
        subject,
        html: htmlBody,
        text: `Payment confirmed #${shortId} · ₱${orderTotal.toFixed(2)}${isCOD ? '. Balance on delivery.' : '.'}`,
      });

      console.log(`📧 Sent payment confirmation to ${email} for order ${orderId}`);
    } catch (error) {
      console.error('❌ Failed to send payment confirmation email:', error);
      // Don't throw - email failure shouldn't break payment confirmation
    }
  }

  /**
   * Sends the customer's single updating invoice (same invoice number per order)
   * after each payment and as late-fees progress.
   */
  static async sendUpdatedInvoiceEmail(params: {
    readonly userId: string;
    readonly orderId: string;
  }): Promise<void> {
    try {
      const { userId, orderId } = params;
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );
      if (rows.length === 0) return;

      const user = rows[0];
      const invoice = await buildUpdatedOrderInvoiceHtml(orderId);
      const shortId = orderId.substring(0, 8).toUpperCase();

      const htmlBody = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(invoice.invoiceTitle)}</title>
</head>
<body style="margin:0;padding:18px;background:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;color:#111827;">
  <div style="max-width:920px;margin:0 auto;background:#fff;border-radius:20px;padding:20px;box-shadow:0 10px 32px rgba(0,0,0,.08);">
    ${invoice.bodyHtml}
  </div>
</body>
</html>`;

      await sendEmail({
        to: user.email,
        subject: invoice.subject,
        html: htmlBody,
        text: `Updated invoice for Order #${shortId}. Balance due: ${invoice.totalBalanceDue.toFixed(2)}.`,
      });
    } catch (error) {
      console.error('❌ Failed to send updated invoice email:', error);
    }
  }

  /**
   * Reminder email at payment default milestones (2 months, 80 days, 90 days).
   */
  static async sendPaymentDefaultWarningEmail(params: {
    readonly userId: string;
    readonly orderId: string;
    readonly payByAt: Date;
    readonly depositAmount: number;
    readonly remainingBalance: number;
  }): Promise<void> {
    try {
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [params.userId],
      );
      if (rows.length === 0) return;

      const user = rows[0];
      const shortId = params.orderId.substring(0, 8).toUpperCase();
      const payByStr = params.payByAt.toISOString().slice(0, 10);

      const subject = `Payment default warning — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Payment Default Reminder',
        greeting: `Hi ${user.full_name},`,
        intro: `Your remaining balance must be paid by ${escapeHtml(payByStr)}.`,
        bodyHtml: `
          <p style="margin:0;font-size:20px;line-height:1.45;color:#333;">Order <strong>#${escapeHtml(shortId)}</strong></p>
          <p style="margin:10px 0 0;font-size:18px;line-height:1.45;color:#333;">Deposit already received: <strong>₱${escapeHtml(params.depositAmount.toFixed(2))}</strong></p>
          <p style="margin:10px 0 0;font-size:18px;line-height:1.45;color:#333;">Balance currently due: <strong>₱${escapeHtml(params.remainingBalance.toFixed(2))}</strong></p>
          <p style="margin:16px 0 0;font-size:18px;line-height:1.55;color:#333;">
            Pay by <strong>${escapeHtml(payByStr)}</strong> or your order will be automatically cancelled and your deposit will be forfeited as a restocking/holding fee.
          </p>
        `,
      });

      await sendEmail({
        to: user.email,
        subject,
        html: htmlBody,
        text: `Order #${shortId}: pay by ${payByStr} or it will be cancelled and your deposit forfeited.`,
      });
    } catch (error) {
      console.error('❌ Failed to send payment default warning email:', error);
    }
  }

  /**
   * Cancellation email for non-payment default (deposit forfeiture).
   */
  static async sendPaymentDefaultCancelledEmail(params: {
    readonly userId: string;
    readonly orderId: string;
    readonly depositAmount: number;
  }): Promise<void> {
    try {
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [params.userId],
      );
      if (rows.length === 0) return;
      const user = rows[0];

      const shortId = params.orderId.substring(0, 8).toUpperCase();
      const subject = `Order cancelled — payment default #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Order Cancelled (Payment Default)',
        greeting: `Hi ${user.full_name},`,
        intro: 'This order was automatically cancelled due to non-payment after the policy period.',
        bodyHtml: `<p style="margin:0;font-size:20px;line-height:1.45;color:#333;">Order <strong>#${escapeHtml(shortId)}</strong></p>
          <p style="margin:10px 0 0;font-size:18px;line-height:1.45;color:#333;">
            Your deposit of <strong>₱${escapeHtml(params.depositAmount.toFixed(2))}</strong> was forfeited as a restocking/holding fee.
          </p>`,
      });

      await sendEmail({
        to: user.email,
        subject,
        html: htmlBody,
        text: `Order #${shortId} was cancelled due to non-payment. Your deposit was forfeited: ₱${params.depositAmount.toFixed(2)}.`,
      });
    } catch (error) {
      console.error('❌ Failed to send payment default cancelled email:', error);
    }
  }

  /**
   * Sends an order shipped email when logistics marks the package in transit.
   */
  static async sendOrderShippedEmail(userId: string, orderId: string): Promise<void> {
    try {
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );
      if (rows.length === 0) return;
      const user = rows[0];
      const shortId = orderId.substring(0, 8).toUpperCase();
      const subject = `Order shipped — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Order Shipped',
        greeting: `Hi ${user.full_name},`,
        intro: 'Your order is now in transit.',
        bodyHtml: `<p style="margin:0;font-size:20px;line-height:1.45;color:#333;">Order <strong>#${escapeHtml(shortId)}</strong> has been shipped and is on the way.</p>`,
      });
      await sendEmail({
        to: user.email,
        subject,
        html: htmlBody,
        text: `Order #${shortId} has been shipped.`,
      });
    } catch (error) {
      console.error('❌ Failed to send order shipped email:', error);
    }
  }

  /**
   * Sends an order delivered email when the order reaches the customer.
   */
  static async sendOrderDeliveredEmail(userId: string, orderId: string): Promise<void> {
    try {
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );
      if (rows.length === 0) return;
      const user = rows[0];
      const shortId = orderId.substring(0, 8).toUpperCase();
      const subject = `Order delivered — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Order Delivered',
        greeting: `Hi ${user.full_name},`,
        intro: 'Your order has been delivered.',
        bodyHtml: `<p style="margin:0;font-size:20px;line-height:1.45;color:#333;">Order <strong>#${escapeHtml(shortId)}</strong> is marked as delivered. Thank you for choosing Wood Home Furniture Trading.</p>`,
      });
      await sendEmail({
        to: user.email,
        subject,
        html: htmlBody,
        text: `Order #${shortId} has been delivered.`,
      });
    } catch (error) {
      console.error('❌ Failed to send order delivered email:', error);
    }
  }

  /**
   * Sends an order cancelled email to the customer.
   */
  static async sendOrderCancelledEmail(userId: string, orderId: string): Promise<void> {
    try {
      const pool = getPool();
      const [rows] = await pool.query<UserRow[]>(
        'SELECT email, full_name FROM users WHERE id = ? LIMIT 1',
        [userId],
      );
      if (rows.length === 0) return;
      const user = rows[0];
      const shortId = orderId.substring(0, 8).toUpperCase();
      const subject = `Order cancelled — #${shortId}`;
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Order Cancelled',
        greeting: `Hi ${user.full_name},`,
        intro: 'Your order has been cancelled.',
        bodyHtml: `<p style="margin:0;font-size:20px;line-height:1.45;color:#333;">Order <strong>#${escapeHtml(shortId)}</strong> is now cancelled. If this was unexpected, contact support from the app.</p>`,
      });
      await sendEmail({
        to: user.email,
        subject,
        html: htmlBody,
        text: `Order #${shortId} has been cancelled.`,
      });
    } catch (error) {
      console.error('❌ Failed to send order cancelled email:', error);
    }
  }

  /**
   * Sends an email verification email to the user after signup.
   * Contains a verification link that the user must click to verify their email.
   */
  static async sendVerificationEmail(
    userEmail: string,
    userName: string,
    verificationToken: string,
    verificationCode: string,
    _frontendUrl?: string,
  ): Promise<void> {
    try {
      const safeCode = escapeHtml(verificationCode);
      const subject = 'Verify your Wood Home Furniture Trading account';
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Welcome to Wood Home Furniture Trading!',
        greeting: `Hi ${userName},`,
        intro: 'Thanks for signing up! To complete your registration and start using Wood Home Furniture Trading, please verify your email address.',
        bodyHtml: `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f8f8f8;border:1px dashed #9a7f72;border-radius:8px;margin:8px 0 4px;">
<tr><td style="padding:18px 14px;text-align:center;">
<p style="margin:0 0 8px;font-size:14px;color:#7b5a4f;font-weight:600;">Your verification code:</p>
<p style="margin:0;font-family:'Courier New',Courier,monospace;font-size:34px;letter-spacing:0.24em;color:#7b5a4f;font-weight:700;white-space:nowrap;">${safeCode}</p>
<p style="margin:10px 0 0;font-size:12px;color:#999;">Enter this code in the app to verify your email.</p>
</td></tr>
</table>`,
        footerNote:
          'This verification code expires in 24 hours. If you did not create this account, you can safely ignore this email.',
      });
      await sendEmail({
        to: userEmail,
        subject,
        html: htmlBody,
        text: `Verify your Wood Home Furniture Trading account.\n\nYour code: ${verificationCode}\n`,
      });

      console.log(`✅ Successfully sent verification email to ${userEmail}`);
    } catch (error) {
      // Log detailed error information to help debug
      const errorDetails = error instanceof Error ? error.message : String(error);
      console.error(`❌ FAILED to send verification email to ${userEmail}`);
      console.error(`   Error details: ${errorDetails}`);
      
      // Check for common SMTP errors and provide helpful messages
      if (errorDetails.includes('Invalid login') || errorDetails.includes('authentication failed')) {
        console.error(`   ⚠️  SMTP authentication failed. Check your SMTP_USERNAME and SMTP_PASSWORD.`);
        console.error(`   ⚠️  For Gmail, make sure you're using an App Password, not your regular password.`);
      } else if (errorDetails.includes('ECONNREFUSED') || errorDetails.includes('connect')) {
        console.error(`   ⚠️  Cannot connect to SMTP server. Check SMTP_HOST and SMTP_PORT.`);
      } else if (errorDetails.includes('timeout')) {
        console.error(`   ⚠️  SMTP connection timed out. Check your network and SMTP settings.`);
      }
      
      // Don't throw - email failure shouldn't break signup, but log it clearly
    }
  }

  /**
   * Customer self-service password reset — link targets the storefront Flutter route.
   */
  static async sendUserPasswordResetEmail(
    userName: string,
    userEmail: string,
    resetLink: string,
  ): Promise<void> {
    try {
      const subject = 'Reset your Wood Home password';
      const safeLink = escapeHtml(resetLink);
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Password reset',
        greeting: `Hi ${userName},`,
        intro:
          'We received a request to reset your password. Use the button below within one hour. If you did not ask for this, ignore this email.',
        bodyHtml: `<p style="margin:0;text-align:center;"><a href="${safeLink}" style="display:inline-block;padding:14px 28px;background:#5D4037;color:#fff;text-decoration:none;border-radius:12px;font-weight:600;">Choose a new password</a></p>
<p style="margin:16px 0 0;font-size:13px;color:#888;word-break:break-all;">${safeLink}</p>`,
        footerNote: 'This link expires in one hour.',
      });
      await sendEmail({
        to: userEmail,
        subject,
        html: htmlBody,
        text: `Reset your Wood Home password:\n${resetLink}\n`,
      });
      console.log(`✅ Sent customer password reset email to ${userEmail}`);
    } catch (error) {
      console.error('❌ Failed to send customer password reset email:', error);
    }
  }

  /**
   * Admin password reset — link opens admin Flutter entry (hash route).
   */
  static async sendAdminPasswordResetEmail(
    adminName: string,
    adminEmail: string,
    resetLink: string,
  ): Promise<void> {
    try {
      const subject = 'Reset your Wood Home admin password';
      const safeLink = escapeHtml(resetLink);
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Admin password reset',
        greeting: `Hi ${adminName},`,
        intro:
          'Use the link below to set a new admin password. It expires in one hour. If you did not request this, contact your super admin.',
        bodyHtml: `<p style="margin:0;text-align:center;"><a href="${safeLink}" style="display:inline-block;padding:14px 28px;background:#5D4037;color:#fff;text-decoration:none;border-radius:12px;font-weight:600;">Reset admin password</a></p>
<p style="margin:16px 0 0;font-size:13px;color:#888;word-break:break-all;">${safeLink}</p>`,
        footerNote: 'This link expires in one hour.',
      });
      await sendEmail({
        to: adminEmail,
        subject,
        html: htmlBody,
        text: `Reset your Wood Home admin password:\n${resetLink}\n`,
      });
      console.log(`✅ Sent admin password reset email to ${adminEmail}`);
    } catch (error) {
      console.error('❌ Failed to send admin password reset email:', error);
    }
  }

  /**
   * Sent when a new admin account is created; includes code + API verify link for webmail.
   */
  static async sendAdminVerificationEmail(
    adminName: string,
    adminEmail: string,
    verificationToken: string,
    verificationCode: string,
  ): Promise<void> {
    try {
      const apiBase = config.publicApiBaseUrl.replace(/\/$/, '');
      const verifyUrl = `${apiBase}/api/admin-auth/verify-email?token=${encodeURIComponent(verificationToken)}&ui=1`;
      const safeCode = escapeHtml(verificationCode);
      const safeVerifyUrl = escapeHtml(verifyUrl);
      const subject = 'Verify your Wood Home admin email';
      const htmlBody = buildWoodHomeTemplate({
        heading: 'Verify admin email',
        greeting: `Hi ${adminName},`,
        intro:
          'Your administrator account was created. Confirm this email to activate sign-in. You can tap the link or enter the code in the admin app.',
        bodyHtml: `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f8f8f8;border:1px dashed #9a7f72;border-radius:8px;margin:8px 0 4px;">
<tr><td style="padding:18px 14px;text-align:center;">
<p style="margin:0 0 8px;font-size:14px;color:#7b5a4f;font-weight:600;">Your verification code:</p>
<p style="margin:0;font-family:'Courier New',Courier,monospace;font-size:34px;letter-spacing:0.24em;color:#7b5a4f;font-weight:700;white-space:nowrap;">${safeCode}</p>
<p style="margin:14px 0 0;font-size:12px;color:#999;">Or verify in the browser:</p>
<p style="margin:8px 0 0;text-align:center;"><a href="${safeVerifyUrl}" style="display:inline-block;padding:12px 22px;background:#5D4037;color:#fff;text-decoration:none;border-radius:12px;font-weight:600;">Verify email</a></p>
</td></tr>
</table>`,
        footerNote:
          'This code and link expire in 24 hours. If you did not expect this email, ignore it.',
      });
      await sendEmail({
        to: adminEmail,
        subject,
        html: htmlBody,
        text: `Verify your Wood Home admin email.\nCode: ${verificationCode}\nLink: ${verifyUrl}\n`,
      });
      console.log(`✅ Sent admin verification email to ${adminEmail}`);
    } catch (error) {
      console.error('❌ Failed to send admin verification email:', error);
    }
  }
}






