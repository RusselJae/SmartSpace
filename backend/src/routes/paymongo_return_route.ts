/**
 * Simple HTML pages after PayMongo redirects (test / default URLs).
 * Override with PAYMONGO_SUCCESS_URL / PAYMONGO_CANCEL_URL to point at your Flutter web URL.
 */
import { Router } from 'express';
import { getPool } from '../config/database';
import { updateOrderStatus } from '../services/order_service';

export const paymongoReturnRouter = Router();

paymongoReturnRouter.get('/success', (_req, res) => {
  res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Payment successful</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; padding: 2rem; line-height: 1.5; color: #333; }
    h1 { color: #2e7d32; }
  </style>
</head>
<body>
  <h1>Payment successful</h1>
  <p>Your payment was received. You can close this tab and return to the SmartSpace app.</p>
  <p><small>If the app does not update immediately, open <strong>Orders</strong> to refresh.</small></p>
</body>
</html>`);
});

paymongoReturnRouter.get('/cancel', (req, res) => {
  const orderId = req.query.orderId as string | undefined;

  // If we can't resolve the order, keep the old simple response.
  if (!orderId) {
    res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Payment cancelled</title>
</head>
<body style="font-family:system-ui;padding:2rem;">
  <h1>Payment cancelled</h1>
  <p>You can close this tab and try again from the app.</p>
</body>
</html>`);
    return;
  }

  (async () => {
    const pool = getPool();
    try {
      const [rows] = await pool.query<any[]>(
        `SELECT payment_status, status FROM orders WHERE id = ? LIMIT 1`,
        [orderId],
      );
      const row = rows[0];
      const paymentStatus = (row?.payment_status ?? '').toString().toLowerCase();

      // If already completed by webhook, don't cancel.
      if (paymentStatus === 'completed') {
        res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Payment processed</title>
</head>
<body style="font-family:system-ui;padding:2rem;">
  <h1>Payment processed</h1>
  <p>The app will update your order automatically.</p>
</body>
</html>`);
        return;
      }

      // Cancel the order to release reserved inventory.
      await updateOrderStatus(orderId, 'cancelled');

      // Mark payment status as failed (keeps UI logic consistent with unpaid/cancelled state).
      await pool.query(`UPDATE orders SET payment_status = 'failed', updated_at = NOW() WHERE id = ?`, [
        orderId,
      ]);

      res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Payment cancelled</title>
</head>
<body style="font-family:system-ui;padding:2rem;">
  <h1>Payment cancelled</h1>
  <p>Your order has been cancelled and inventory has been released.</p>
  <p><small>If the app does not update immediately, open <strong>Orders</strong> to refresh.</small></p>
</body>
</html>`);
    } catch (e) {
      console.error('PayMongo cancel route:', e);
      res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Payment cancelled</title>
</head>
<body style="font-family:system-ui;padding:2rem;">
  <h1>Payment cancelled</h1>
  <p>You can close this tab and try again from the app.</p>
</body>
</html>`);
    }
  })();
});

/*
  Old version:
  paymongoReturnRouter.get('/cancel', (_req, res) => {
    res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Payment cancelled</title>
</head>
<body style="font-family:system-ui;padding:2rem;">
  <h1>Payment cancelled</h1>
  <p>You can close this tab and try again from the app.</p>
</body>
</html>`);
});
*/
