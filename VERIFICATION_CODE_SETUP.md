# Verification Code Setup

This document describes the manual verification code feature that has been added to email verification.

## Overview

Users can now verify their email in two ways:
1. **Click the verification link** in the email (existing method)
2. **Enter a 6-character code** manually in the app (new method)

This provides better UX for users who:
- Can't click links in their email client
- Prefer manual entry
- Are on devices where deep linking doesn't work

## What Was Implemented

### Backend Changes

1. **Database Schema** (`backend/sql/add_verification_code.sql`)
   - Added `verification_code` (VARCHAR(8)) field
   - Added index on `verification_code` for fast lookups

2. **User Model** (`backend/src/models/user.ts`)
   - Added `verificationCode?: string` field

3. **User Service** (`backend/src/services/user_service.ts`)
   - Added `generateVerificationCode()` - creates 6-character code (A-Z, 2-9, excludes confusing chars)
   - Updated `createUser()` to generate both token and code
   - Added `findUserByVerificationCode()` to lookup users by code
   - Added `verifyUserEmailByCode()` to verify using code
   - Updated `resendVerificationToken()` to also generate new code
   - All verification functions now clear both token and code after verification

4. **User Routes** (`backend/src/routes/user_route.ts`)
   - Added `POST /api/users/verify-email-code` endpoint
   - Updated resend endpoint to include code in email

5. **Email Service** (`backend/src/services/email_service.ts`)
   - Updated `sendVerificationEmail()` to accept and display verification code
   - Email now shows code prominently in a styled box
   - Code is displayed in large, easy-to-read format

### Frontend Changes

1. **Auth Service** (`app/lib/services/auth_service.dart`)
   - Added `verifyEmailByCode()` method to verify using code

2. **Email Verification Screen** (`app/lib/screens/views/email_verification_screen.dart`)
   - Added code input field with auto-formatting
   - Auto-converts to uppercase
   - Limits to 6 characters
   - Large, centered text input for easy entry
   - "Verify Code" button
   - Divider between code entry and resend email options

## Setup Instructions

### 1. Run Database Migration

Execute the SQL migration to add verification code field:

```bash
mysql -u your_username -p smartspace_ar < backend/sql/add_verification_code.sql
```

Or manually run:
```sql
ALTER TABLE users
ADD COLUMN verification_code VARCHAR(8) NULL,
ADD INDEX idx_verification_code (verification_code);
```

### 2. Restart Backend Server

After running the migration, restart your backend server:

```bash
cd backend
npm run dev
```

## How It Works

### Code Generation

- **Format:** 6 characters
- **Characters:** A-Z (excluding I, O) and 2-9 (excluding 0, 1)
- **Purpose:** Easy to read and type, avoids confusing characters
- **Example:** `ABC234`, `XYZ789`, `DEF567`

### Verification Flow

1. **User signs up** → Backend generates both token and code
2. **Email sent** → Contains both link and code
3. **User options:**
   - **Option A:** Click link → Opens app → Auto-verifies
   - **Option B:** Enter code → Tap "Verify Code" → Verifies
4. **After verification** → Both token and code are cleared
5. **User can login** → Email is now verified

### Code Input Features

- **Auto-uppercase:** Converts lowercase to uppercase automatically
- **Character filtering:** Only allows A-Z and 0-9, removes special characters
- **Length limit:** Maximum 6 characters
- **Large display:** 24px font, letter-spacing for easy reading
- **Centered text:** Easy to see what you're typing

## Email Format

The verification email now includes:

1. **Verification Code Box:**
   - Large, prominent display
   - 6-character code in monospace font
   - Instructions to enter in app

2. **Verification Link Button:**
   - "Or Click Here to Verify" button
   - Opens app via deep link

3. **Web URL (fallback):**
   - Full URL for manual copy/paste
   - Works if deep linking fails

## Testing

### Test Code Entry

1. Sign up with a new account
2. Check email for verification code
3. Open app → Email Verification screen
4. Enter the 6-character code
5. Tap "Verify Code"
6. Should verify and redirect to login

### Test Link Clicking

1. Sign up with a new account
2. Check email for verification link
3. Click the link
4. Should open app and auto-verify
5. Redirects to login

### Test Both Methods

1. Sign up with a new account
2. Try entering the code manually
3. If that works, try clicking the link (should say already verified)
4. Both methods should work independently

## Code Format

The verification code uses:
- **Length:** 6 characters
- **Format:** Alphanumeric (A-Z, 2-9)
- **Excludes:** 0, 1, I, O (to avoid confusion)
- **Case:** Always uppercase
- **Example codes:** `ABC234`, `XYZ789`, `DEF567`

## Security Notes

- Codes expire after 24 hours (same as tokens)
- Codes are single-use (cleared after verification)
- Codes are case-insensitive (converted to uppercase)
- Codes are stored securely in database
- Codes are cryptographically random

## Troubleshooting

### Code Not Working

- Check code is exactly 6 characters
- Verify code hasn't expired (24 hours)
- Make sure code is entered correctly (no spaces, correct characters)
- Check backend logs for verification errors

### Code Not in Email

- Verify database migration was run
- Check backend logs for email sending errors
- Verify SMTP is configured correctly
- Check spam folder

### Both Code and Link Don't Work

- Check backend is running
- Verify database has verification_code column
- Check backend logs for errors
- Restart backend server












