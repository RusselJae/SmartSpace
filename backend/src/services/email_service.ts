import nodemailer from 'nodemailer';
import { RowDataPacket } from 'mysql2';
import sgMail from '@sendgrid/mail';
import { Resend } from 'resend';
import { config } from '../config/env';
import { getPool } from '../config/database';

type UserRow = RowDataPacket & {
  readonly email: string;
  readonly full_name: string;
};

/** Avoid breaking HTML email bodies when names contain <>&. */
const escapeHtml = (value: string): string =>
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

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

const sendEmail = async (payload: EmailPayload): Promise<void> => {
  // Prefer SendGrid when configured. This works without a custom domain
  // as long as you verified a Single Sender in the SendGrid dashboard.
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
    console.warn('⚠️ Email delivery disabled: neither SendGrid nor Resend is configured.');
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

export class EmailService {
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
      const htmlBody = `<!DOCTYPE html><html><head><meta charset="utf-8"/></head>
<body style="font-family:system-ui,-apple-system,sans-serif;line-height:1.5;color:#222;max-width:420px;margin:0;padding:16px;">
<p>Hi ${escapeHtml(userName)},</p>
<p>Order <strong>#${escapeHtml(shortId)}</strong> has expired.</p>
<p>Wood Home Furniture Trading</p>
</body></html>`;
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
      const htmlBody = `<!DOCTYPE html><html><head><meta charset="utf-8"/></head>
<body style="font-family:system-ui,-apple-system,sans-serif;line-height:1.5;color:#222;max-width:420px;margin:0;padding:16px;">
<p>Hi ${escapeHtml(user.full_name)},</p>
<p>Order <strong>#${escapeHtml(shortId)}</strong> · Total <strong>₱${escapeHtml(totalStr)}</strong></p>
<p>Complete payment in the app under <strong>Orders</strong>.</p>
</body></html>`;
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
      const htmlBody = `<!DOCTYPE html><html><head><meta charset="utf-8"/></head>
<body style="font-family:system-ui,-apple-system,sans-serif;line-height:1.5;color:#222;max-width:420px;margin:0;padding:16px;">
<p>Hi ${escapeHtml(userName)},</p>
<p>Order <strong>#${escapeHtml(shortId)}</strong> · ₱${escapeHtml(orderTotal.toFixed(2))}</p>
<p>Wood Home Furniture Trading</p>
</body></html>`;
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
      const htmlBody = `<!DOCTYPE html><html><head><meta charset="utf-8"/></head>
<body style="font-family:system-ui,-apple-system,sans-serif;line-height:1.5;color:#222;max-width:420px;margin:0;padding:16px;">
<p>Hi ${escapeHtml(userName)},</p>
<p>Payment confirmed for order <strong>#${escapeHtml(shortId)}</strong> · ₱${escapeHtml(orderTotal.toFixed(2))}</p>
${isCOD ? `<p>Balance due on delivery.</p>` : ''}
<p>Wood Home Furniture Trading</p>
</body></html>`;
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
      const appVerifyUrl = `smartspace://verify-email?token=${encodeURIComponent(verificationToken)}`;

      const apiOrigin =
        config.publicApiBaseUrl.trim().length > 0
          ? config.publicApiBaseUrl.trim()
          : config.environment === 'development'
            ? `http://localhost:${config.port}`
            : '';
      const browserVerifyUrl =
        apiOrigin.length > 0
          ? `${apiOrigin}/api/users/verify-email?token=${encodeURIComponent(verificationToken)}&ui=1`
          : '';

      const safeName = escapeHtml(userName);
      const safeCode = escapeHtml(verificationCode);

      const subject = 'Your verification code — Wood Home';
      const safeBrowser = browserVerifyUrl ? escapeHtml(browserVerifyUrl) : '';
      const safeApp = escapeHtml(appVerifyUrl);
      const browserButtonRow = browserVerifyUrl
        ? `<tr><td align="center" style="padding:0 0 12px;">
<a href="${safeBrowser}" style="display:inline-block;padding:14px 28px;background:#6D28D9;color:#ffffff;text-decoration:none;border-radius:10px;font-weight:600;font-size:15px;font-family:system-ui,-apple-system,sans-serif;">Verify in browser</a>
</td></tr>`
        : '';
      const htmlBody = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:24px 12px;background:#f4f4f5;font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td align="center">
<table role="presentation" style="max-width:420px;width:100%;border-collapse:separate;border-spacing:0;border-radius:14px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);" cellpadding="0" cellspacing="0" border="0">
<tr><td style="background:#6D28D9;padding:22px 20px;text-align:center;border-radius:14px 14px 0 0;">
<p style="margin:0;font-size:18px;font-weight:700;color:#ffffff;letter-spacing:-0.02em;">Your verification code</p>
</td></tr>
<tr><td style="background:#ffffff;padding:24px 22px 20px;">
<p style="margin:0 0 14px;color:#111827;font-size:15px;line-height:1.5;">Hi ${safeName},</p>
<p style="margin:0 0 16px;color:#4b5563;font-size:14px;line-height:1.5;">Use this code to verify your email:</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="background:#f3f4f6;border-radius:10px;padding:18px 12px;text-align:center;">
<span style="font-size:26px;font-weight:700;letter-spacing:0.28em;color:#6D28D9;font-family:ui-monospace,Menlo,Consolas,monospace;">${safeCode}</span>
</td></tr></table>
<p style="margin:14px 0 0;color:#9ca3af;font-size:12px;line-height:1.45;">Valid 24 hours. Do not share this code.</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:22px;">
${browserButtonRow}
<tr><td align="center" style="padding:0;">
<a href="${safeApp}" style="display:inline-block;padding:14px 28px;background:#7c3aed;color:#ffffff;text-decoration:none;border-radius:10px;font-weight:600;font-size:15px;font-family:system-ui,-apple-system,sans-serif;">Open Wood Home app</a>
</td></tr>
</table>
</td></tr>
<tr><td style="background:#f3f4f6;padding:14px 16px;text-align:center;border-radius:0 0 14px 14px;">
<p style="margin:0;font-size:11px;color:#9ca3af;line-height:1.4;">Wood Home Furniture Trading</p>
</td></tr>
</table>
</td></tr></table>
</body></html>`;
      await sendEmail({
        to: userEmail,
        subject,
        html: htmlBody,
        text:
          `Code: ${verificationCode}\n` +
          (browserVerifyUrl ? `Verify (browser): ${browserVerifyUrl}\n` : '') +
          `Open app: ${appVerifyUrl}\n`,
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
}






