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

/** Only allow http(s) logo URLs so `src` cannot be abused. */
const sanitizeEmailLogoUrl = (raw: string): string => {
  const trimmed = raw.trim();
  if (!trimmed) return '';
  try {
    const u = new URL(trimmed);
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

      const subject = `Order Expired - Order #${orderId.substring(0, 8)}`;
      const htmlBody = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Order Expired</title>
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: linear-gradient(135deg, #b71c1c 0%, #d32f2f 100%); padding: 30px; border-radius: 12px 12px 0 0; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px; font-weight: 600;">Order Expired</h1>
          </div>
          <div style="background: #ffffff; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 12px 12px;">
            <p style="font-size: 16px; margin: 0 0 20px 0;">Hi ${userName},</p>
            <p style="font-size: 16px; margin: 0 0 20px 0;">Your order could not be confirmed and is now marked as <strong>expired</strong>.</p>
            <p style="font-size: 16px; margin: 0 0 20px 0;">You can place a new order any time and complete the payment to proceed.</p>

            <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
              <p style="margin: 0 0 10px 0; font-weight: 600; font-size: 14px; color: #666;">Order Number:</p>
              <p style="margin: 0; font-size: 18px; font-weight: 700; color: #b71c1c;">#${orderId.substring(0, 8).toUpperCase()}</p>
            </div>

            <p style="font-size: 16px; margin: 20px 0 0 0;">If you believe this is a mistake, please contact support or place your order again.</p>

            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; text-align: center;">
              <p style="font-size: 12px; color: #999; margin: 0;">Wood Home Furniture Trading</p>
            </div>
          </div>
        </body>
        </html>
      `;
      await sendEmail({
        to: email,
        subject,
        html: htmlBody,
        text: `Order Expired - Order #${orderId.substring(0, 8).toUpperCase()}`,
      });

      console.log(`📧 Sent expired-order notice to ${email} for order ${orderId}`);
    } catch (error) {
      console.error('❌ Failed to send expired-order email:', error);
      // Do not throw; email failure should not break order updates
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

      // Email content
      const subject = `Order Confirmed - Order #${orderId.substring(0, 8)}`;
      const htmlBody = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Order Confirmed</title>
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: linear-gradient(135deg, #5D4037 0%, #3E2723 100%); padding: 30px; border-radius: 12px 12px 0 0; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px; font-weight: 600;">Order Confirmed!</h1>
          </div>
          <div style="background: #ffffff; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 12px 12px;">
            <p style="font-size: 16px; margin: 0 0 20px 0;">Hi ${userName},</p>
            <p style="font-size: 16px; margin: 0 0 20px 0;">Great news! Your order has been confirmed and is being processed.</p>
            
            <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
              <p style="margin: 0 0 10px 0; font-weight: 600; font-size: 14px; color: #666;">Order Number:</p>
              <p style="margin: 0 0 20px 0; font-size: 18px; font-weight: 700; color: #5D4037;">#${orderId.substring(0, 8).toUpperCase()}</p>
              
              <p style="margin: 0 0 10px 0; font-weight: 600; font-size: 14px; color: #666;">Total Amount:</p>
              <p style="margin: 0; font-size: 20px; font-weight: 700; color: #5D4037;">₱${orderTotal.toFixed(2)}</p>
            </div>
            
            <p style="font-size: 16px; margin: 20px 0 0 0;">You can track your order status in the app.</p>
            <p style="font-size: 16px; margin: 20px 0 0 0;">Thank you for your purchase!</p>
            
            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; text-align: center;">
              <p style="font-size: 12px; color: #999; margin: 0;">Wood Home Furniture Trading</p>
            </div>
          </div>
        </body>
        </html>
      `;
      await sendEmail({
        to: email,
        subject,
        html: htmlBody,
        text: `Order Confirmed - Order #${orderId.substring(0, 8).toUpperCase()}`,
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
      const paymentType = isCOD ? 'Downpayment' : 'Full Payment';

      // Email content
      const subject = `Payment Confirmed - Order #${orderId.substring(0, 8)}`;
      const htmlBody = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Payment Confirmed</title>
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: linear-gradient(135deg, #4CAF50 0%, #2E7D32 100%); padding: 30px; border-radius: 12px 12px 0 0; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px; font-weight: 600;">Payment Confirmed!</h1>
          </div>
          <div style="background: #ffffff; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 12px 12px;">
            <p style="font-size: 16px; margin: 0 0 20px 0;">Hi ${userName},</p>
            <p style="font-size: 16px; margin: 0 0 20px 0;">Great news! Your ${paymentType.toLowerCase()} has been confirmed and your order is being processed.</p>
            
            <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0;">
              <p style="margin: 0 0 10px 0; font-weight: 600; font-size: 14px; color: #666;">Order Number:</p>
              <p style="margin: 0 0 20px 0; font-size: 18px; font-weight: 700; color: #4CAF50;">#${orderId.substring(0, 8).toUpperCase()}</p>
              
              <p style="margin: 0 0 10px 0; font-weight: 600; font-size: 14px; color: #666;">Payment Status:</p>
              <p style="margin: 0 0 20px 0; font-size: 16px; font-weight: 600; color: #4CAF50;">${paymentType} Confirmed ✓</p>
              
              <p style="margin: 0 0 10px 0; font-weight: 600; font-size: 14px; color: #666;">Total Amount:</p>
              <p style="margin: 0; font-size: 20px; font-weight: 700; color: #4CAF50;">₱${orderTotal.toFixed(2)}</p>
            </div>
            
            ${isCOD ? '<p style="font-size: 16px; margin: 20px 0 0 0; color: #666;">The remaining balance will be collected upon delivery.</p>' : ''}
            
            <p style="font-size: 16px; margin: 20px 0 0 0;">You can track your order status in the app.</p>
            <p style="font-size: 16px; margin: 20px 0 0 0;">Thank you for your purchase!</p>
            
            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; text-align: center;">
              <p style="font-size: 12px; color: #999; margin: 0;">Wood Home Furniture Trading</p>
            </div>
          </div>
        </body>
        </html>
      `;
      await sendEmail({
        to: email,
        subject,
        html: htmlBody,
        text: `Payment Confirmed - Order #${orderId.substring(0, 8).toUpperCase()}`,
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
      // Custom scheme opens the installed app (Android/iOS) when the user taps the link.
      // encodeURIComponent keeps tokens with + / = safe inside the query string.
      const appVerifyUrl = `smartspace://verify-email?token=${encodeURIComponent(verificationToken)}`;

      const safeName = escapeHtml(userName);
      const safeCode = escapeHtml(verificationCode);
      const logoSrc = sanitizeEmailLogoUrl(config.emailBranding.logoUrl);
      const logoBlock = logoSrc
        ? `<img src="${escapeHtml(logoSrc)}" width="120" height="120" alt="Wood Home Furniture Trading" style="display:block;margin:0 auto 8px;border-radius:16px;max-width:120px;height:auto;border:0;" />`
        : `<table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:0 auto 12px;">
            <tr><td style="width:72px;height:72px;background:#5D4037;border-radius:18px;text-align:center;vertical-align:middle;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:22px;font-weight:700;color:#ffffff;letter-spacing:-0.5px;">WH</td></tr>
          </table>`;

      // Table-based layout: better rendering in Gmail/Outlook. Apple-inspired spacing and warm neutrals.
      const subject = 'Verify your Wood Home Furniture Trading account';
      const htmlBody = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="light">
  <meta name="supported-color-schemes" content="light">
  <title>Verify your email</title>
</head>
<body style="margin:0;padding:0;background-color:#F2EDE8;-webkit-text-size-adjust:100%;">
  <div style="display:none;max-height:0;overflow:hidden;mso-hide:all;">
    Your Wood Home verification code: ${safeCode}
  </div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#F2EDE8;padding:24px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background-color:#FFFFFF;border-radius:20px;overflow:hidden;box-shadow:0 8px 32px rgba(93,64,55,0.12);border:1px solid rgba(93,64,55,0.08);">
          <tr>
            <td style="background:linear-gradient(145deg,#A1887F 0%,#6D4C41 48%,#5D4037 100%);padding:28px 24px 24px;text-align:center;">
              ${logoBlock}
              <h1 style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;font-size:22px;font-weight:600;color:#FFFFFF;line-height:1.3;letter-spacing:-0.02em;">
                Wood Home Furniture Trading
              </h1>
              <p style="margin:10px 0 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:15px;font-weight:500;color:rgba(255,255,255,0.92);">
                Confirm your email to finish signing up
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:28px 28px 8px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
              <p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#4E342E;">Hi ${safeName},</p>
              <p style="margin:0 0 24px;font-size:15px;line-height:1.6;color:#5D4037;">
                Thanks for joining us. Use the code below in the app, or tap the button on the phone where Wood Home is installed to verify in one step.
              </p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#FBF8F5;border-radius:14px;border:1px dashed #BCAAA4;">
                <tr>
                  <td style="padding:22px 20px;text-align:center;">
                    <p style="margin:0 0 8px;font-size:12px;font-weight:600;letter-spacing:0.08em;text-transform:uppercase;color:#8D6E63;">Verification code</p>
                    <p style="margin:0;font-family:'SF Mono',ui-monospace,Menlo,Consolas,monospace;font-size:28px;font-weight:700;color:#5D4037;letter-spacing:0.42em;white-space:nowrap;">${safeCode}</p>
                    <p style="margin:12px 0 0;font-size:12px;color:#A1887F;line-height:1.4;">Enter this code on the verification screen in the app.</p>
                  </td>
                </tr>
              </table>
              <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:28px auto 0;">
                <tr>
                  <td align="center" style="border-radius:14px;background:linear-gradient(145deg,#8D6E63 0%,#5D4037 100%);">
                    <a href="${appVerifyUrl}" style="display:inline-block;padding:16px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:16px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:14px;">
                      Open the app to verify
                    </a>
                  </td>
                </tr>
              </table>
              <p style="margin:20px 0 0;text-align:center;font-size:12px;line-height:1.5;color:#A1887F;">
                If the button does not respond, long-press and open in browser is not available for this link—use the code above or tap the link on your device:
                <br /><br />
                <a href="${appVerifyUrl}" style="color:#6D4C41;font-weight:600;word-break:break-all;">${escapeHtml(appVerifyUrl)}</a>
              </p>
              <p style="margin:24px 0 0;font-size:13px;line-height:1.55;color:#8D6E63;">
                This code expires in 24 hours. If you did not create an account, you can ignore this message.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:0 28px 24px;text-align:center;">
              <p style="margin:0;padding-top:20px;border-top:1px solid #EFEBE9;font-size:11px;color:#BCAAA4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
                Wood Home Furniture Trading
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
      await sendEmail({
        to: userEmail,
        subject,
        html: htmlBody,
        text:
          `Verify your Wood Home Furniture Trading account.\n\n` +
          `Your code: ${verificationCode}\n\n` +
          `Open in the app (copy this on your phone if needed):\n${appVerifyUrl}\n`,
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






