/**
 * PayMongo return URLs: redirect browser → `smartspace://paymongo-return` so the Flutter app opens.
 * Override with PAYMONGO_SUCCESS_URL / PAYMONGO_CANCEL_URL only if you host equivalent pages.
 */
import { Router } from 'express';
import { getPool } from '../config/database';
import { updateOrderStatus } from '../services/order_service';
import { buildPaymongoAppReturnUrl, paymongoReturnRedirectPage } from './paymongo_return_html';

export const paymongoReturnRouter = Router();

paymongoReturnRouter.get('/success', (req, res) => {
  const orderId = typeof req.query.orderId === 'string' ? req.query.orderId : undefined;
  const mtoRequestId = typeof req.query.mtoRequestId === 'string' ? req.query.mtoRequestId : undefined;
  const appUrl = buildPaymongoAppReturnUrl({ status: 'success', orderId, mtoRequestId });
  const html = paymongoReturnRedirectPage(
    appUrl,
    'Payment successful',
    'Your payment was received. Opening the Wood Home app…',
  );
  res.type('html').send(html);
});

paymongoReturnRouter.get('/cancel', (req, res) => {
  const orderId = req.query.orderId as string | undefined;
  const mtoRequestId = typeof req.query.mtoRequestId === 'string' ? req.query.mtoRequestId : undefined;

  const sendCancelToApp = (title: string, line: string) => {
    const appUrl = buildPaymongoAppReturnUrl({ status: 'cancel', orderId, mtoRequestId });
    res.type('html').send(paymongoReturnRedirectPage(appUrl, title, line));
  };

  if (!orderId) {
    sendCancelToApp('Payment cancelled', 'You can try again from the app.');
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

      if (paymentStatus === 'completed') {
        const appUrl = buildPaymongoAppReturnUrl({ status: 'success', orderId, mtoRequestId });
        res.type('html').send(
          paymongoReturnRedirectPage(
            appUrl,
            'Payment processed',
            'Your payment is already complete. Opening the app…',
          ),
        );
        return;
      }

      // Do not cancel an order that already has a down payment / balance-payment lifecycle.
      // Closing the browser during "pay again" should simply return the user to the app.
      if (paymentStatus === 'downpayment_received') {
        sendCancelToApp(
          'Payment cancelled',
          'Balance payment was not completed. Your order is still active and you can try again from Orders.',
        );
        return;
      }

      await updateOrderStatus(orderId, 'cancelled');

      await pool.query(`UPDATE orders SET payment_status = 'failed', updated_at = NOW() WHERE id = ?`, [
        orderId,
      ]);

      sendCancelToApp(
        'Payment cancelled',
        'Checkout was closed. Your order was cancelled; you can place it again from the app.',
      );
    } catch (e) {
      console.error('PayMongo cancel route:', e);
      sendCancelToApp('Payment cancelled', 'You can close this tab and return to the app.');
    }
  })();
});

