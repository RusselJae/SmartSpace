# Backend Payment Implementation Guide

## Overview
This document describes the backend endpoints and services implemented for payment proof upload, admin confirmation, and auto-cancellation.

## Endpoints

### 1. Payment Proof Upload
**POST** `/api/payment-proofs/upload`

Uploads a payment proof screenshot for an order.

**Request:**
- Method: `POST`
- Content-Type: `multipart/form-data`
- Body:
  - `file`: Image file (jpg, jpeg, png, webp, gif) - max 10MB
  - `orderId`: Order ID string

**Response:**
```json
{
  "success": true,
  "data": {
    "fileName": "proof_o1234567_1234567890.jpg",
    "filePath": "o1234567/proof_o1234567_1234567890.jpg",
    "downloadUrl": "/uploads/payment-proofs/o1234567/proof_o1234567_1234567890.jpg",
    "orderId": "o1234567890"
  }
}
```

**Behavior:**
- Validates order exists
- Checks order is not already cancelled or confirmed
- Uploads image to `uploads/payment-proofs/{orderId}/`
- Updates order status to `pending_payment_verification`
- Sets payment_status to `pending`

---

### 2. Admin Payment Confirmation
**POST** `/api/orders/:id/confirm-payment`

Admin endpoint to confirm payment proof and update order status.

**Request:**
- Method: `POST`
- Body:
```json
{
  "adminId": "admin123"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Payment confirmed successfully"
}
```

**Behavior:**
- Verifies order exists
- Determines payment status based on payment method:
  - COD: `downpayment_paid` (20% paid, 80% remaining)
  - GCash: `completed` (full payment)
- Updates order status:
  - COD: stays `pending` (waiting for delivery)
  - GCash: changes to `confirmed`
- Sends confirmation email to user

---

### 3. Auto-Cancel Unpaid Orders
**POST** `/api/orders/auto-cancel`

Manually trigger auto-cancellation of unpaid orders (for testing/admin).

**Request:**
- Method: `POST`
- No body required

**Response:**
```json
{
  "success": true,
  "message": "Auto-cancelled 3 unpaid order(s)",
  "cancelledCount": 3
}
```

**Behavior:**
- Finds orders that:
  - Status is `pending` or `pending_payment_verification`
  - Payment status is `pending`
  - Created more than 30 minutes ago
- Cancels these orders:
  - Sets status to `cancelled`
  - Sets payment_status to `failed`
- Returns count of cancelled orders

**Note:** In production, this should be called automatically by a cron job (see Auto-Cancellation Job below).

---

## Auto-Cancellation Job

### Setup

The auto-cancellation job runs automatically when the server starts (if `node-cron` is installed).

**Install node-cron:**
```bash
npm install node-cron
npm install --save-dev @types/node-cron
```

**Manual Setup (if node-cron not installed):**
Set up a cron job or scheduled task to call:
```
POST http://localhost:4000/api/orders/auto-cancel
```

**Recommended Schedule:**
- Every 5 minutes (default in code)
- Or every 10 minutes for lower server load

### Implementation

The job is defined in `backend/src/jobs/auto_cancel_job.ts` and automatically starts when the server initializes.

---

## Database Migrations

### 1. Add Downpayment Columns
Run: `app/sql/add_downpayment_columns.sql`

Adds:
- `downpayment_amount` column
- `remaining_balance` column
- Updates `payment_method` enum to include 'gcash'
- Updates `payment_status` enum to include 'downpayment_paid'

### 2. Add Payment Proof URL Column
Run: `app/sql/add_payment_proof_url_column.sql`

Adds:
- `payment_proof_url` column (VARCHAR(500))
- Index on `payment_status` for faster queries

---

## Email Notifications

### Payment Confirmation Email

Sent when admin confirms payment proof.

**Trigger:** Admin calls `/api/orders/:id/confirm-payment`

**Content:**
- Order number
- Payment status (Downpayment/Full Payment)
- Total amount
- For COD: Note about remaining balance on delivery

**Configuration:**
Set SMTP credentials in `.env`:
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password
SMTP_FROM=SmartSpace AR <your_email@gmail.com>
```

---

## Order Status Flow

```
pending → pending_payment_verification → confirmed → shipped → delivered
                ↓ (30 min timeout)
            cancelled
```

### Payment Status Flow

**COD Orders:**
```
pending → downpayment_paid → (delivery) → completed
```

**GCash Orders:**
```
pending → completed
```

---

## Testing

### Test Payment Proof Upload
```bash
curl -X POST http://localhost:4000/api/payment-proofs/upload \
  -F "file=@payment_screenshot.jpg" \
  -F "orderId=o1234567890"
```

### Test Admin Confirmation
```bash
curl -X POST http://localhost:4000/api/orders/o1234567890/confirm-payment \
  -H "Content-Type: application/json" \
  -d '{"adminId": "admin123"}'
```

### Test Auto-Cancellation
```bash
curl -X POST http://localhost:4000/api/orders/auto-cancel
```

---

## Security Considerations

1. **File Upload Validation:**
   - Only image files allowed (jpg, jpeg, png, webp, gif)
   - Max file size: 10MB
   - Files stored in order-specific directories

2. **Order Validation:**
   - Cannot upload proof for cancelled orders
   - Cannot upload proof for confirmed orders
   - Order must exist before upload

3. **Admin Confirmation:**
   - Should require admin authentication (add middleware)
   - Logs admin ID for audit trail

4. **Auto-Cancellation:**
   - Only cancels orders older than 30 minutes
   - Only cancels orders with pending payment
   - Idempotent (safe to run multiple times)

---

## Next Steps

1. **Add Admin Authentication:**
   - Add authentication middleware to `/api/orders/:id/confirm-payment`
   - Verify admin has permission to confirm payments

2. **Add Payment Proof URL Column:**
   - Run migration: `app/sql/add_payment_proof_url_column.sql`
   - Update order service to use the column

3. **Add Admin Panel UI:**
   - List orders with `pending_payment_verification` status
   - Show payment proof images
   - Add "Confirm Payment" button

4. **Monitor Auto-Cancellation:**
   - Add logging/metrics for cancelled orders
   - Alert if cancellation rate is high

5. **Email Templates:**
   - Customize email templates for better branding
   - Add order details in email

---

## Troubleshooting

### Payment proof upload fails
- Check file size (max 10MB)
- Verify file is an image (jpg, jpeg, png, webp, gif)
- Ensure order exists and is not cancelled/confirmed
- Check `uploads/payment-proofs/` directory permissions

### Auto-cancellation not running
- Check if `node-cron` is installed
- Verify server logs for scheduler start message
- Manually call `/api/orders/auto-cancel` to test

### Email not sending
- Verify SMTP credentials in `.env`
- Check Gmail App Password is set correctly
- Review server logs for email errors




















