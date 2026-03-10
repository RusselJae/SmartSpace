# Deep Linking Setup for Email Verification

This document explains how email verification deep linking works and how to configure it.

## How It Works

When users click the verification link in their email:

1. **Mobile Apps (Android/iOS):**
   - Link format: `smartspace://verify-email?token=...`
   - Opens the app directly via custom URL scheme
   - App extracts token and verifies email

2. **Web Apps:**
   - Link format: `https://yourdomain.com/verify-email?token=...`
   - Opens in browser
   - Flutter web app extracts token from URL and verifies

## Configuration

### Android Deep Linking

Already configured in `app/android/app/src/main/AndroidManifest.xml`:
- Custom scheme: `smartspace://`
- HTTP/HTTPS links: `https://*/*/verify-email`

### iOS Deep Linking

Already configured in `app/ios/Runner/Info.plist`:
- Custom scheme: `smartspace://`

### Backend Configuration

Set `FRONTEND_URL` in `backend/.env`:

```env
# For web apps
FRONTEND_URL=https://yourdomain.com

# For local development (web)
FRONTEND_URL=http://localhost:3000
```

## Testing Deep Links

### Android

1. **Test custom scheme:**
   ```bash
   adb shell am start -a android.intent.action.VIEW -d "smartspace://verify-email?token=test123"
   ```

2. **Test HTTP link:**
   ```bash
   adb shell am start -a android.intent.action.VIEW -d "https://yourdomain.com/verify-email?token=test123"
   ```

### iOS

1. **Test in Safari:**
   - Open Safari on iOS device
   - Type: `smartspace://verify-email?token=test123`
   - Should open the app

2. **Test HTTP link:**
   - Open: `https://yourdomain.com/verify-email?token=test123`
   - Should open in app if configured

### Web

1. Open browser and navigate to:
   ```
   http://localhost:3000/verify-email?token=test123
   ```

## Troubleshooting

### Link Doesn't Open App

**Android:**
- Check AndroidManifest.xml has intent filters
- Verify app is installed
- Try uninstalling and reinstalling app
- Check logcat for errors: `adb logcat | grep -i intent`

**iOS:**
- Check Info.plist has CFBundleURLTypes
- Verify app is installed
- Try uninstalling and reinstalling app

### Link Opens But Token Not Extracted

- Check app logs for deep link parsing errors
- Verify token is in URL query parameters
- Check VerifyEmailScreen is receiving token

### Works on Web But Not Mobile

- Mobile requires custom URL scheme (`smartspace://`)
- Make sure email contains the custom scheme link
- Check deep linking is configured in AndroidManifest.xml and Info.plist

## Current Implementation

The email verification link uses:
- **Primary:** `smartspace://verify-email?token=...` (works for mobile)
- **Fallback:** `{FRONTEND_URL}/verify-email?token=...` (works for web)

Both links are included in the email, with the mobile scheme as the primary button link.












