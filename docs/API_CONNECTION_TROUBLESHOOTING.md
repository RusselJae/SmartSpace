# API Connection Troubleshooting Guide

## Problem: App works with localhost but not with IPv4 address

### Quick Checklist

1. ✅ **Backend is running** - You should see `🚀 SmartSpaceBackend listening on port 4000`
2. ✅ **Backend is listening on 0.0.0.0** - Check backend/src/index.ts (should have `server.listen(config.port, '0.0.0.0', ...)`)
3. ✅ **URL format is correct** - Must be `http://YOUR_IP:4000/api` (not missing port or protocol)
4. ✅ **Windows Firewall allows port 4000** - Check Windows Defender Firewall settings
5. ✅ **Both devices on same network** - Only needed if accessing from another device

---

## Step-by-Step Troubleshooting

### Step 1: Verify Backend is Running

```bash
cd backend
npm run dev
```

You should see:
```
🚀 SmartSpaceBackend listening on port 4000
📡 Server accessible at:
   - http://localhost:4000
   - http://127.0.0.1:4000
   - http://[YOUR_IPv4_ADDRESS]:4000
```

### Step 2: Find Your IPv4 Address

**Windows:**
```bash
ipconfig
```
Look for "IPv4 Address" under your active network adapter (usually Wi-Fi or Ethernet).

**Example output:**
```
Wireless LAN adapter Wi-Fi:
   IPv4 Address. . . . . . . . . . . : 192.168.254.106
```

### Step 3: Test Backend Directly in Browser

Open your browser and go to:
```
http://YOUR_IPv4_ADDRESS:4000/api/health
```

**If this works:** The backend is accessible. The issue is likely in the Flutter app configuration.

**If this doesn't work:** 
- Check Windows Firewall (see Step 4)
- Verify backend is listening on 0.0.0.0 (see backend/src/index.ts)
- Make sure you're using the correct IPv4 address

### Step 4: Check Windows Firewall

1. Open **Windows Defender Firewall**
2. Click **Advanced settings**
3. Click **Inbound Rules** → **New Rule**
4. Select **Port** → **Next**
5. Select **TCP** and enter port **4000** → **Next**
6. Select **Allow the connection** → **Next**
7. Check all profiles → **Next**
8. Name it "SmartSpace Backend" → **Finish**

Alternatively, allow Node.js through firewall:
1. Windows Defender Firewall → **Allow an app through firewall**
2. Find **Node.js** and check both **Private** and **Public**

### Step 5: Update Flutter App Configuration

**For Web App (index.html):**
```javascript
window.flutterConfig = {
  apiBaseUrl: 'http://192.168.254.106:4000/api',  // Replace with YOUR IP
  apiTimeout: 10
};
```

**Important:** The URL MUST include:
- ✅ Protocol: `http://`
- ✅ IP address: `192.168.254.106`
- ✅ Port: `:4000`
- ✅ Path: `/api`

**Wrong formats:**
- ❌ `192.168.254.106/api` (missing http:// and port)
- ❌ `http://192.168.254.106/api` (missing port)
- ❌ `192.168.254.106:4000/api` (missing http://)

### Step 6: Clear Browser Cache

After changing the API URL:
1. **Hard refresh:** `Ctrl+Shift+R` (Windows) or `Cmd+Shift+R` (Mac)
2. Or **Clear cache:** Browser settings → Clear browsing data → Cached images and files

### Step 7: Check Browser Console

Open browser DevTools (F12) and check:
1. **Console tab** - Look for API connection errors
2. **Network tab** - Check if requests are being made and what the response is

Common errors:
- `ERR_CONNECTION_REFUSED` - Backend not running or firewall blocking
- `CORS error` - Backend CORS configuration issue (shouldn't happen with our setup)
- `404 Not Found` - Wrong URL path

### Step 8: Verify Backend CORS Configuration

The backend should allow all origins in development. Check `backend/src/app.ts`:
```typescript
app.use(cors({
  origin: (origin, callback) => {
    // Should allow all origins in development
    callback(null, true);
  },
  // ...
}));
```

---

## Common Issues and Solutions

### Issue: "ERR_CONNECTION_REFUSED"

**Causes:**
- Backend not running
- Backend listening only on localhost (not 0.0.0.0)
- Windows Firewall blocking port 4000
- Wrong IPv4 address

**Solutions:**
1. Start backend: `cd backend && npm run dev`
2. Verify backend/src/index.ts has: `server.listen(config.port, '0.0.0.0', ...)`
3. Check Windows Firewall (see Step 4)
4. Verify IPv4 address with `ipconfig`

### Issue: "CORS error" or "Blocked by CORS policy"

**Causes:**
- Backend CORS not configured correctly
- Origin not matching CORS rules

**Solutions:**
1. Check backend/src/app.ts CORS configuration
2. Should allow all origins in development: `callback(null, true)`
3. Restart backend after changes

### Issue: URL missing port number

**Symptoms:**
- Browser shows: `http://192.168.254.106/api/health` (no port)
- Should be: `http://192.168.254.106:4000/api/health`

**Solutions:**
1. Check index.html - ensure URL includes `:4000`
2. The app will auto-add port if missing, but it's better to include it
3. Clear browser cache and hard refresh

### Issue: Works on same computer but not from another device

**Causes:**
- Devices not on same network
- Backend not listening on 0.0.0.0
- Router blocking local network traffic

**Solutions:**
1. Ensure both devices connected to same Wi-Fi/router
2. Verify backend is listening on 0.0.0.0 (not just localhost)
3. Check router settings (some routers block device-to-device communication)

---

## Testing Your Setup

### Test 1: Backend Health Check
```bash
# In browser or curl
http://YOUR_IPv4_ADDRESS:4000/api/health
```

Expected response:
```json
{
  "success": true,
  "data": {
    "status": "ok",
    "database": "connected"
  }
}
```

### Test 2: Flutter App Console
Open browser DevTools (F12) → Console tab. You should see:
```
🌐 Using API URL from window.flutterConfig: http://192.168.254.106:4000/api
✅ Final normalized API URL: http://192.168.254.106:4000/api
🔍 Checking API availability at: http://192.168.254.106:4000/api/health
```

### Test 3: Network Tab
Open browser DevTools (F12) → Network tab:
1. Refresh the app
2. Look for request to `/api/health`
3. Check status code (should be 200)
4. Check request URL (should include port :4000)

---

## Still Not Working?

1. **Check backend logs** - Look for connection attempts
2. **Check browser console** - Look for detailed error messages
3. **Try localhost first** - If localhost works, the issue is network/firewall related
4. **Test with curl/Postman** - Bypass browser to isolate the issue:
   ```bash
   curl http://YOUR_IPv4_ADDRESS:4000/api/health
   ```

If curl works but browser doesn't, it's likely a CORS or browser cache issue.
If curl doesn't work, it's a network/firewall/backend configuration issue.















