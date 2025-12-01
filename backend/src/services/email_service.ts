import nodemailer from 'nodemailer';
import { RowDataPacket } from 'mysql2';
import { config } from '../config/env';
import { getPool } from '../config/database';

type UserRow = RowDataPacket & {
  readonly email: string;
  readonly full_name: string;
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

export class EmailService {
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
              <p style="margin: 0; font-size: 20px; font-weight: 700; color: #5D4037;">$${orderTotal.toFixed(2)}</p>
            </div>
            
            <p style="font-size: 16px; margin: 20px 0 0 0;">You can track your order status in the SmartSpace app.</p>
            <p style="font-size: 16px; margin: 20px 0 0 0;">Thank you for your purchase!</p>
            
            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; text-align: center;">
              <p style="font-size: 12px; color: #999; margin: 0;">SmartSpace AR</p>
            </div>
          </div>
        </body>
        </html>
      `;

      // Lazily initialize the transporter to keep startup fast when email is
      // not needed (e.g., local dev scripts). We create it here so that the
      // first send attempts to build the connection, yet every subsequent send
      // reuses the cached instance for efficiency.
      if (!cachedTransporter) {
        cachedTransporter = buildTransporter();
      }

      // Bail out if email remains disabled even after the build attempt. This
      // situation only occurs when credentials are missing, so the earlier
      // warning should already hint at the fix.
      if (!cachedTransporter) {
        return;
      }

      // Gmail requires either OAuth or an App Password (recommended). We assume
      // an App Password is present and use STARTTLS (port 587) by default.
      await cachedTransporter.sendMail({
        from: config.email.from,
        to: email,
        subject,
        html: htmlBody,
      });

      // Keep a slim log trail so we can trace successful sends without dumping
      // the entire email body, which could contain sensitive information.
      console.log(`📧 Sent order confirmation to ${email} for order ${orderId}`);
    } catch (error) {
      console.error('❌ Failed to send order confirmation email:', error);
      // Don't throw - email failure shouldn't break order confirmation
    }
  }
}






