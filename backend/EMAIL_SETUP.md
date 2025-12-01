# Email Service Setup

The email service is currently configured to log email notifications to the console. To enable actual email sending in production, integrate with one of the following services:

## Gmail + Nodemailer (Recommended)

1. **Enable App Passwords**
   - Turn on 2FA for the Gmail account you want to send from.
   - Visit https://myaccount.google.com/apppasswords and generate an App Password (choose “Mail” / “Other”).
   - Copy the 16‑character password; this is what we use for `SMTP_PASSWORD`.

2. **Set environment variables** (either in `backend/.env` or your shell):
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_SECURE=false        # Gmail STARTTLS
   SMTP_USERNAME=your_email@gmail.com
   SMTP_PASSWORD=the_app_password_from_step_1
   SMTP_FROM=SmartSpace AR <your_email@gmail.com>
   ```

3. **Install dependencies** (already added to package.json, but run once locally):
   ```bash
   npm install
   ```

4. **Restart the backend** so the updated env vars are loaded.

### Alternative Providers

#### Option 1: SendGrid

1. Install SendGrid:
```bash
npm install @sendgrid/mail
```

2. Update `email_service.ts` to use SendGrid API

#### Option 2: AWS SES

1. Install AWS SDK:
```bash
npm install @aws-sdk/client-ses
```

2. Configure AWS credentials and update `email_service.ts`

## Current Behavior

- ✅ Email service logs all order confirmations to console
- ✅ Email notifications are triggered when admin confirms an order
- ✅ Email includes order details (ID, total, customer name)
- ⚠️ Actual email sending requires integration with email service provider

## Testing

To test email functionality:
1. Place an order as a user
2. Go to admin panel → Orders
3. Change order status from "pending" to "confirmed"
4. Check console logs for email notification details






