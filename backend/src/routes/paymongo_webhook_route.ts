/**
 * PayMongo webhooks — must use raw JSON body (see app.ts).
 * Register URL in PayMongo dashboard: https://your-api/api/webhooks/paymongo
 * Events: checkout_session.payment.paid, payment.paid
 */
import { Router } from 'express';
import {
  extractOrderIdFromPaymongoEvent,
  extractPaymentAmountPesosFromPaymongoEvent,
  verifyPaymongoWebhookSignature,
} from '../services/paymongo_service';
import { markOrderPaidViaPaymongo, markOrderPaymentFailedViaPaymongo } from '../services/order_service';
import { asyncHandler } from '../utils/async_handler';

export const paymongoWebhookRouter = Router();

const isFailedPaymentEvent = (event: Record<string, unknown>): boolean => {
  const raw = JSON.stringify(event);
  return raw.includes('checkout_session.payment.failed') || raw.includes('"payment.failed"');
};

/**
 * Returns true if this event indicates a successful charge we should reconcile.
 */
const isSuccessfulPaymentEvent = (event: Record<string, unknown>): boolean => {
  const raw = JSON.stringify(event);
  // Avoid acting on refunds/failures in success branch.
  if (isFailedPaymentEvent(event) || raw.includes('payment.refunded')) return false;
  return raw.includes('checkout_session.payment.paid') || raw.includes('"payment.paid"');
};

paymongoWebhookRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const raw = req.body as Buffer;
    if (!Buffer.isBuffer(raw)) {
      return res.status(400).json({ success: false, message: 'Expected raw body' });
    }

    const sig = req.headers['paymongo-signature'] as string | undefined;
    if (!verifyPaymongoWebhookSignature(raw, sig)) {
      return res.status(401).json({ success: false, message: 'Invalid signature' });
    }

    let event: Record<string, unknown>;
    try {
      event = JSON.parse(raw.toString('utf8')) as Record<string, unknown>;
    } catch {
      return res.status(400).json({ success: false, message: 'Invalid JSON' });
    }

    if (!isSuccessfulPaymentEvent(event) && !isFailedPaymentEvent(event)) {
      return res.json({ received: true, ignored: true });
    }

    const orderId = extractOrderIdFromPaymongoEvent(event);
    if (!orderId) {
      console.warn('PayMongo webhook: no order_id in payload');
      return res.json({ received: true, orderId: null });
    }

    try {
      if (isFailedPaymentEvent(event)) {
        await markOrderPaymentFailedViaPaymongo(orderId);
      } else {
        const amountPesos = extractPaymentAmountPesosFromPaymongoEvent(event);
        const eventId = typeof event['id'] === 'string' ? (event['id'] as string) : undefined;
        await markOrderPaidViaPaymongo(orderId, { amountPesos, eventId });
      }
    } catch (e) {
      console.error('PayMongo webhook reconciliation:', e);
      return res.status(500).json({ success: false });
    }

    return res.json({ received: true, orderId });
  }),
);
