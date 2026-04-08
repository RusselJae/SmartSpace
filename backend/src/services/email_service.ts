import nodemailer from 'nodemailer';
import { RowDataPacket } from 'mysql2';
import { Resend } from 'resend';
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
let cachedResend: Resend | null = null;

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
      const resend = getResendClient();
      if (resend == null) return;

      // Resend send (HTTPS API). Unlike SMTP, this works reliably on Render Free.
      await resend.emails.send({
        from: config.email.from,
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
      const resend = getResendClient();
      if (resend == null) return;

      await resend.emails.send({
        from: config.email.from,
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
      const resend = getResendClient();
      if (resend == null) return;

      await resend.emails.send({
        from: config.email.from,
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
    frontendUrl?: string,
  ): Promise<void> {
    try {
      // Use frontend URL from config if not provided, fallback to localhost
      const frontendBaseUrl = frontendUrl ?? config.frontend.url;
      
      // Construct verification URLs
      // For mobile apps: use custom URL scheme (smartspace://)
      // For web: use HTTP/HTTPS URL
      // The email will contain both, with mobile scheme as primary
      const mobileUrl = `smartspace://verify-email?token=${verificationToken}`;
      const webUrl = `${frontendBaseUrl}/verify-email?token=${verificationToken}`;
      // Universal link / hosted fallback (once deployed, FRONTEND_URL should be your real domain)
      // This lets iOS/Android open the installed app if configured, otherwise it opens the web.
      const universalUrl = webUrl;

      // Use the app link as the primary CTA.
      const verificationUrl = mobileUrl;

      // Email content with modern, clean design following Apple HIG principles
      const subject = 'Verify your Wood Home Furniture Trading account';
      const htmlBody = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Verify Your Email</title>
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: linear-gradient(135deg, #8D6E63 0%, #5D4037 100%); padding: 30px; border-radius: 12px 12px 0 0; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px; font-weight: 600;">Welcome to Wood Home Furniture Trading!</h1>
          </div>
          <div style="background: #ffffff; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 12px 12px;">
            <p style="font-size: 16px; margin: 0 0 20px 0;">Hi ${userName},</p>
            <p style="font-size: 16px; margin: 0 0 20px 0;">Thanks for signing up! To complete your registration and start using Wood Home Furniture Trading, please verify your email address.</p>
            
            <div style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; text-align: center; border: 2px dashed #8D6E63;">
              <p style="font-size: 14px; color: #666; margin: 0 0 10px 0; font-weight: 600;">Your verification code:</p>
              <p style="font-size: 32px; font-weight: 700; color: #8D6E63; margin: 0; letter-spacing: 4px; font-family: 'Courier New', monospace;">${verificationCode}</p>
              <p style="font-size: 12px; color: #999; margin: 10px 0 0 0;">Enter this code in the app to verify your email</p>
            </div>
            
            <div style="text-align: center; margin: 30px 0;">
              <a href="${verificationUrl}" 
                 style="display: inline-block; background: linear-gradient(135deg, #8D6E63 0%, #5D4037 100%); color: white; text-decoration: none; padding: 14px 32px; border-radius: 8px; font-weight: 600; font-size: 16px; box-shadow: 0 4px 12px rgba(141, 110, 99, 0.3);">
                Open the app to verify
              </a>
            </div>

            <div style="margin: 18px 0 0 0; text-align: center;">
              <p style="font-size: 13px; color: #666; margin: 0 0 10px 0;">
                If the button doesn’t open the app:
              </p>
              <a href="${universalUrl}"
                 style="display: inline-block; color: #8D6E63; text-decoration: underline; font-weight: 600; font-size: 13px; margin: 0 10px 6px 10px;">
                Verify in browser
              </a>
            </div>
            
            <div style="margin: 14px 0 0 0; text-align: center;">
              <p style="font-size: 12px; color: #999; margin: 0;">
                Deployed app links will use <strong>${frontendBaseUrl}</strong> as the fallback domain.
              </p>
            </div>
            
            <p style="font-size: 14px; color: #666; margin: 20px 0 0 0;">This verification code and link will expire in 24 hours.</p>
            <p style="font-size: 14px; color: #666; margin: 10px 0 0 0;">If you didn't create an account with Wood Home Furniture Trading, you can safely ignore this email.</p>
            
            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; text-align: center;">
              <p style="font-size: 12px; color: #999; margin: 0;">Wood Home Furniture Trading</p>
            </div>
          </div>
        </body>
        </html>
      `;

      const resend = getResendClient();
      if (resend == null) {
        console.error(
          `⚠️ EMAIL VERIFICATION FAILED: Resend not configured. ` +
            `Set RESEND_API_KEY. Email verification was NOT sent to: ${userEmail}`,
        );
        return;
      }

      // Attempt to send the email via Resend (no SMTP required).
      await resend.emails.send({
        from: config.email.from,
        to: userEmail,
        subject,
        html: htmlBody,
        text: `Verify your Wood Home Furniture Trading account.\n\nYour code: ${verificationCode}`,
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






