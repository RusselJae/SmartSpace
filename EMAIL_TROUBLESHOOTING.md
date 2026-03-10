# Email Verification Troubleshooting Guide

If you're not receiving verification emails, follow these steps to diagnose and fix the issue.

## Quick Checklist

1. ✅ **Check Backend Console Logs** - Look for email-related warnings or errors
2. ✅ **Verify SMTP Configuration** - Check your `backend/.env` file
3. ✅ **Test Email Connection** - Verify SMTP credentials work
4. ✅ **Check Spam Folder** - Emails might be filtered

## Step 1: Check Backend Logs

When you start your backend server, you should see one of these messages:

### ✅ Email Configured (Good)
```
✅ Email service configured
   Host: smtp.gmail.com:587
   From: SmartSpace AR <your_email@gmail.com>
```

### ⚠️ Email NOT Configured (Problem)
```
⚠️  EMAIL SERVICE NOT CONFIGURED
═══════════════════════════════════════════════════════════
Email verification will NOT work until SMTP is configured.
...
```

**If you see the warning**, your SMTP credentials are missing. Continue to Step 2.

## Step 2: Configure SMTP in backend/.env

Create or update `backend/.env` with these variables:

```env
# SMTP Configuration (Gmail Example)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password_here
SMTP_FROM=SmartSpace AR <your_email@gmail.com>
```

### For Gmail Setup:

1. **Enable 2-Factor Authentication**
   - Go to: https://myaccount.google.com/security
   - Enable 2-Step Verification

2. **Generate App Password**
   - Visit: https://myaccount.google.com/apppasswords
   - Select "Mail" and your device
   - Copy the 16-character password (no spaces)

3. **Use App Password**
   - Use the App Password (not your regular Gmail password) as `SMTP_PASSWORD`
   - Example: `SMTP_PASSWORD=abcd efgh ijkl mnop` (or remove spaces)

### For Other Email Providers:

#### Outlook/Hotmail
```env
SMTP_HOST=smtp-mail.outlook.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=your_email@outlook.com
SMTP_PASSWORD=your_password
```

#### Yahoo
```env
SMTP_HOST=smtp.mail.yahoo.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=your_email@yahoo.com
SMTP_PASSWORD=your_app_password
```

#### Custom SMTP (SendGrid, Mailgun, etc.)
```env
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=apikey
SMTP_PASSWORD=your_sendgrid_api_key
SMTP_FROM=SmartSpace AR <noreply@yourdomain.com>
```

## Step 3: Restart Backend Server

After updating `.env`, **restart your backend server**:

```bash
cd backend
npm run dev
```

You should now see:
```
✅ Email service configured
```

## Step 4: Test Email Sending

1. **Sign up with a new account**
2. **Check backend console** for these messages:

### ✅ Success
```
✅ Successfully sent verification email to user@example.com
```

### ❌ Failure - Check Error Message

#### Authentication Failed
```
❌ FAILED to send verification email to user@example.com
   Error details: Invalid login
   ⚠️  SMTP authentication failed. Check your SMTP_USERNAME and SMTP_PASSWORD.
   ⚠️  For Gmail, make sure you're using an App Password, not your regular password.
```

**Fix:** 
- Verify you're using an App Password (not regular password) for Gmail
- Check username and password are correct
- Make sure there are no extra spaces in `.env` file

#### Connection Refused
```
❌ FAILED to send verification email to user@example.com
   Error details: ECONNREFUSED
   ⚠️  Cannot connect to SMTP server. Check SMTP_HOST and SMTP_PORT.
```

**Fix:**
- Verify `SMTP_HOST` is correct for your provider
- Check `SMTP_PORT` (usually 587 for STARTTLS, 465 for SSL)
- Check firewall/network settings

#### Timeout
```
❌ FAILED to send verification email to user@example.com
   Error details: timeout
   ⚠️  SMTP connection timed out. Check your network and SMTP settings.
```

**Fix:**
- Check internet connection
- Verify SMTP server is accessible
- Try different port (587 vs 465)

## Step 5: Check Email Delivery

### Check These Locations:

1. **Inbox** - Check your email inbox
2. **Spam/Junk Folder** - Emails might be filtered
3. **Promotions Tab** (Gmail) - Check all tabs
4. **Email Filters** - Check if filters are blocking emails

### Email Should Contain:

- **Subject:** "Verify your SmartSpace account"
- **From:** The address you set in `SMTP_FROM`
- **Verification Link:** Click to verify your email

## Common Issues & Solutions

### Issue: "SMTP credentials missing" Warning

**Cause:** Environment variables not set

**Solution:**
1. Create `backend/.env` file if it doesn't exist
2. Add all SMTP variables (see Step 2)
3. Restart backend server

### Issue: "Invalid login" Error

**Cause:** Wrong password or username

**Solution:**
- For Gmail: Use App Password, not regular password
- Verify username matches exactly (case-sensitive for some providers)
- Check for extra spaces in `.env` file values

### Issue: "Connection refused" Error

**Cause:** Wrong SMTP host or port

**Solution:**
- Verify SMTP_HOST is correct for your provider
- Check SMTP_PORT (587 for STARTTLS, 465 for SSL)
- Some providers require `SMTP_SECURE=true` for port 465

### Issue: Email Sent But Not Received

**Cause:** Email delivery issues

**Solution:**
- Check spam folder
- Verify recipient email address is correct
- Check email provider's sending limits
- Wait a few minutes (some providers delay delivery)

### Issue: Works Locally But Not in Production

**Cause:** Environment variables not set in production

**Solution:**
- Set environment variables in your hosting platform
- For Heroku: `heroku config:set SMTP_HOST=...`
- For Docker: Add to docker-compose.yml or .env
- For Vercel/Netlify: Set in dashboard environment variables

## Testing Email Configuration

You can test your email setup by:

1. **Sign up a new user** - Should trigger verification email
2. **Check backend logs** - Look for success/error messages
3. **Check email inbox** - Verify email arrives

## Still Not Working?

If emails still aren't working after following these steps:

1. **Check Backend Logs** - Look for specific error messages
2. **Verify .env File** - Make sure variables are set correctly
3. **Test SMTP Manually** - Use a tool like `nodemailer` test script
4. **Check Email Provider** - Some providers have sending limits or restrictions
5. **Try Different Provider** - Test with a different email service

## Need Help?

If you're still having issues:

1. Copy the exact error message from backend console
2. Check which step you're stuck on
3. Verify your `.env` file has all required variables
4. Check that backend server was restarted after changing `.env`

## Security Notes

- ⚠️ **Never commit `.env` file to git** - It contains sensitive credentials
- ✅ **Use App Passwords** - Don't use your main email password
- ✅ **Rotate Passwords** - Change App Passwords periodically
- ✅ **Limit Access** - Only trusted services should have SMTP credentials













