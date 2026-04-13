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

      const walnut = '#5C4033';
      const walnutMid = '#6D4C41';
      const subject = 'Verify your email — Wood Home';
      const safeEmailAddr = escapeHtml(userEmail);
      const hrefBrowser = browserVerifyUrl ? escapeHtml(browserVerifyUrl) : '';
      const hrefApp = escapeHtml(appVerifyUrl);
      const hrefFacebook = escapeHtml(config.brand.facebookUrl);
      const logoSrc = safeEmailImageUrl(config.emailBranding.logoUrl);
      const fbIconSrc = safeEmailImageUrl(config.brand.facebookIconUrl);
      const logoBlock = logoSrc
        ? `<img src="${escapeHtml(logoSrc)}" alt="Wood Home" width="140" style="display:block;margin:0 auto 12px;max-width:160px;width:100%;height:auto;border:0;"/>`
        : `<p style="margin:0 0 8px;font-size:20px;font-weight:700;color:${walnutMid};letter-spacing:-0.02em;font-family:Poppins,Helvetica,Arial,sans-serif;">Wood Home</p>`;
      const fbFooterBlock =
        fbIconSrc.length > 0
          ? `<a href="${hrefFacebook}" style="display:inline-block;text-decoration:none;color:${walnutMid};font-family:Poppins,Helvetica,Arial,sans-serif;">
<img src="${escapeHtml(fbIconSrc)}" alt="Facebook" width="36" height="36" style="display:block;margin:0 auto 8px;border:0;"/>
<span style="font-size:14px;font-weight:600;text-decoration:underline;">Facebook</span>
</a>`
          : `<a href="${hrefFacebook}" style="color:${walnutMid};font-weight:600;text-decoration:underline;font-size:14px;font-family:Poppins,Helvetica,Arial,sans-serif;">Facebook</a>`;
      const btnBase = `display:block;width:100%;max-width:300px;margin:0 auto;box-sizing:border-box;text-align:center;padding:16px 24px;background:${walnut};color:#ffffff;text-decoration:none;border-radius:10px;font-weight:600;font-size:15px;font-family:Poppins,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%;`;
      const browserCta = browserVerifyUrl
        ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:12px 0 0;">
<tr><td align="center" style="padding:0 8px;">
<a href="${hrefBrowser}" style="${btnBase}">Verify in browser</a>
</td></tr></table>`
        : '';
      const htmlBody = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"/>
<meta name="x-apple-disable-message-reformatting"/>
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap" rel="stylesheet"/>
</head>
<body style="margin:0;padding:0;background:#f0f0f0;font-family:Poppins,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f0f0f0;"><tr><td align="center" style="padding:20px 12px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="max-width:400px;width:100%;">
<tr><td align="center" style="padding:0 0 16px;">${logoBlock}</td></tr>
<tr><td style="background:#ffffff;border:1px solid #e8e8e8;border-radius:14px;padding:28px 22px 26px;">
<p style="margin:0 0 10px;font-size:22px;font-weight:700;color:#1a1a1a;line-height:1.25;font-family:Poppins,Helvetica,Arial,sans-serif;">Let's verify your email</p>
<p style="margin:0 0 20px;font-size:15px;line-height:1.5;color:#333333;font-family:Poppins,Helvetica,Arial,sans-serif;">Hi ${safeName}, confirm <strong style="color:${walnut};font-weight:600;">${safeEmailAddr}</strong> with the code below.</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="background:#f7f7f7;border:1px solid #eeeeee;border-radius:10px;padding:18px 12px;text-align:center;">
<span style="font-size:24px;font-weight:700;letter-spacing:0.22em;color:${walnut};font-family:'Courier New',Courier,monospace;">${safeCode}</span>
</td></tr></table>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:22px;">
<tr><td align="center" style="padding:0 8px;">
<a href="${hrefApp}" style="${btnBase}">Open Wood Home app</a>
</td></tr>
</table>
${browserCta}
</td></tr>
<tr><td align="center" style="padding:22px 12px 8px;">
<p style="margin:0 0 4px;font-size:15px;font-weight:700;color:${walnutMid};font-family:Poppins,Helvetica,Arial,sans-serif;">Wood Home</p>
<p style="margin:0 0 14px;font-size:12px;color:#888888;font-family:Poppins,Helvetica,Arial,sans-serif;">Furniture you can trust.</p>
<p style="margin:0 0 14px;font-size:11px;color:#aaaaaa;line-height:1.45;font-family:Poppins,Helvetica,Arial,sans-serif;">© ${new Date().getFullYear()} Wood Home Furniture Trading</p>
<p style="margin:0;text-align:center;line-height:1.4;">${fbFooterBlock}</p>
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






