# Email Verification Setup

This document describes the email verification feature that has been implemented for user signup.

## Overview

Users must verify their email address after signing up before they can login. This ensures that:
- Users provide valid email addresses
- Email addresses belong to the user
- Users can receive important notifications

## What Was Implemented

### Backend Changes

1. **Database Schema** (`backend/sql/add_email_verification.sql`)
   - Added `email_verified` (BOOLEAN, default FALSE)
   - Added `verification_token` (VARCHAR(255))
   - Added `verification_token_expires` (TIMESTAMP)
   - Added index on `verification_token` for fast lookups

2. **User Model** (`backend/src/models/user.ts`)
   - Added `emailVerified: boolean`
   - Added `verificationToken?: string`
   - Added `verificationTokenExpires?: Date`

3. **User Service** (`backend/src/services/user_service.ts`)
   - Updated `createUser()` to generate verification token on signup
   - Added `verifyUserEmail()` to verify tokens
   - Added `resendVerificationToken()` to generate new tokens
   - Added `findUserByVerificationToken()` to lookup users by token
   - All queries updated to include verification fields

4. **Email Service** (`backend/src/services/email_service.ts`)
   - Added `sendVerificationEmail()` method
   - Sends beautifully formatted HTML email with verification link
   - Uses existing SMTP configuration

5. **User Routes** (`backend/src/routes/user_route.ts`)
   - Updated signup endpoint to send verification email automatically
   - Added `GET /api/users/verify-email?token=...` endpoint
   - Added `POST /api/users/:id/resend-verification` endpoint

6. **Environment Config** (`backend/src/config/env.ts`)
   - Added email configuration section
   - Supports SMTP_HOST, SMTP_PORT, SMTP_SECURE, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM

### Frontend Changes

1. **User Model** (`app/lib/models/user.dart`)
   - Added `emailVerified` field
   - Added `verificationToken` and `verificationTokenExpires` fields
   - Updated `fromJson()`, `toJson()`, and `copyWith()` methods

2. **Auth Service** (`app/lib/services/auth_service.dart`)
   - Updated `signIn()` to check `emailVerified` before allowing login
   - Added `verifyEmail()` method to verify tokens
   - Added `resendVerificationEmail()` method

3. **Email Verification Screen** (`app/lib/screens/views/email_verification_screen.dart`)
   - New screen shown after signup
   - Displays user's email address
   - Provides "Resend Email" button
   - Links to sign in page
   - Follows Apple HIG design principles

4. **Signup Flow** (`app/lib/screens/views/sign_up.dart`)
   - Updated to redirect to email verification screen instead of welcome screen
   - Users see verification instructions immediately after signup

## Setup Instructions

### 1. Run Database Migration

Execute the SQL migration to add verification fields:

```bash
mysql -u your_username -p smartspace_ar < backend/sql/add_email_verification.sql
```

Or manually run:
```sql
ALTER TABLE users
ADD COLUMN email_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN verification_token VARCHAR(255) NULL,
ADD COLUMN verification_token_expires TIMESTAMP NULL,
ADD INDEX idx_verification_token (verification_token);
```

### 2. Configure Email Settings

Add these environment variables to your `backend/.env` file:

```env
# SMTP Configuration (Gmail example)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password
SMTP_FROM=SmartSpace AR <your_email@gmail.com>
```

**For Gmail:**
1. Enable 2-Factor Authentication
2. Generate an App Password: https://myaccount.google.com/apppasswords
3. Use the App Password as `SMTP_PASSWORD`

**For other providers:**
- Adjust `SMTP_HOST`, `SMTP_PORT`, and `SMTP_SECURE` accordingly
- See `backend/EMAIL_SETUP.md` for more details

### 3. Restart Backend Server

After updating environment variables, restart your backend server:

```bash
cd backend
npm run dev
```

## How It Works

### Signup Flow

1. User completes signup form (email, name, birthday, username, password)
2. Backend creates user account with `email_verified = false`
3. Backend generates secure verification token (expires in 24 hours)
4. Backend sends verification email automatically
5. User is redirected to email verification screen
6. User receives email with verification link

### Verification Flow

1. User clicks verification link in email
2. Link points to: `http://your-backend/api/users/verify-email?token=...`
3. Backend validates token and expiration
4. Backend sets `email_verified = true` and clears token
5. User can now login

### Login Flow

1. User attempts to login
2. Backend checks if `email_verified = true`
3. If not verified, login is blocked with error message
4. If verified, login proceeds normally

### Resend Verification

1. User clicks "Resend Email" on verification screen
2. Backend generates new token and expiration
3. Backend sends new verification email
4. User can click new link to verify

## Testing

### Test Signup

1. Sign up with a new email address
2. Check that you're redirected to verification screen
3. Check your email inbox for verification email
4. Click the verification link
5. Try to login - should succeed

### Test Login Blocking

1. Sign up with a new email
2. Don't verify email
3. Try to login immediately
4. Should see error: "Please verify your email address before signing in"

### Test Resend

1. Sign up with a new email
2. On verification screen, click "Resend Email"
3. Check inbox for new email
4. Verify with new link

## Troubleshooting

### Email Not Sending

- Check SMTP credentials in `.env`
- Check backend logs for email errors
- Verify SMTP settings are correct for your provider
- Check spam folder

### Verification Link Not Working

- Check that token hasn't expired (24 hours)
- Verify backend is running and accessible
- Check backend logs for errors
- Ensure database migration was run

### Login Still Works Without Verification

- Verify database migration was applied
- Check that `email_verified` column exists
- Restart backend server
- Clear app cache/data

## Security Notes

- Verification tokens are cryptographically random (32 bytes)
- Tokens expire after 24 hours
- Tokens are single-use (cleared after verification)
- Email verification is required before login
- Tokens are stored securely in database

## Future Enhancements

- Add "Verify Email" button in user profile
- Add email change verification flow
- Add rate limiting on resend requests
- Add email verification reminder emails
- Add admin ability to manually verify emails













