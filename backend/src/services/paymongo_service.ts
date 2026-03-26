/**
 * PayMongo Checkout API (test / live keys via PAYMONGO_SECRET_KEY).
 *
 * Docs: https://developers.paymongo.com/reference/create-a-checkout
 *
 * Amounts are in centavos (1 PHP = 100 centavos).
 * Webhook signature: https://developers.paymongo.com/docs/webhooks
 */
import { createHmac, timingSafeEqual } from 'crypto';
import { config } from '../config/env';

const PAYMONGO_API = 'https://api.paymongo.com/v1';

export type PaymongoCheckoutResult = {
  readonly checkoutSessionId: string;
  readonly checkoutUrl: string;
};

/**
 * Create a hosted Checkout Session and return the URL to redirect the customer.
 */
export const createPaymongoCheckoutSession = async (params: {
  readonly orderId: string;
  readonly amountPesos: number;
  readonly description: string;
  readonly successUrl: string;
  readonly cancelUrl: string;
}): Promise<PaymongoCheckoutResult> => {
  const secret = config.paymongo.secretKey;
  if (!secret) {
    throw new Error('PayMongo is not configured (missing PAYMONGO_SECRET_KEY)');
  }

  // PHP: smallest unit is centavo — multiply by 100 and round to avoid float drift
  const amountCentavos = Math.round(params.amountPesos * 100);
  if (amountCentavos < 100) {
    throw new Error('Order amount must be at least ₱1.00');
  }

  const auth = Buffer.from(`${secret}:`).toString('base64');

  const body = {
    data: {
      attributes: {
        line_items: [
          {
            currency: 'PHP',
            amount: amountCentavos,
            name: params.description,
            quantity: 1,
            description: `Order ${params.orderId}`,
          },
        ],
        // Restrict checkout options to GCash only.
        payment_method_types: ['gcash'],
        success_url: params.successUrl,
        cancel_url: params.cancelUrl,
        description: params.description,
        metadata: {
          order_id: params.orderId,
        },
      },
    },
  };

  const response = await fetch(`${PAYMONGO_API}/checkout_sessions`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const json = (await response.json()) as Record<string, unknown>;

  if (!response.ok) {
    const errors = json['errors'] as unknown;
    console.error('PayMongo checkout_sessions error:', JSON.stringify(errors ?? json));
    // Surface PayMongo detail in the message so the app / Network tab shows why (401, invalid key, etc.)
    const detail =
      typeof errors === 'string'
        ? errors
        : errors != null
          ? JSON.stringify(errors)
          : JSON.stringify(json);
    throw new Error(`PayMongo API error ${response.status}: ${detail}`);
  }

  const data = json['data'] as Record<string, unknown> | undefined;
  const id = data?.['id'] as string | undefined;
  const attributes = data?.['attributes'] as Record<string, unknown> | undefined;
  const checkoutUrl = attributes?.['checkout_url'] as string | undefined;

  if (!id || !checkoutUrl) {
    console.error('PayMongo unexpected response:', JSON.stringify(json));
    throw new Error('PayMongo returned no checkout_url');
  }

  return { checkoutSessionId: id, checkoutUrl };
};

/**
 * Verify `paymongo-signature` header (t=timestamp, v1=hexdigest).
 * If webhook secret is unset (local dev), verification is skipped — **not for production**.
 */
export const verifyPaymongoWebhookSignature = (
  rawBody: Buffer,
  signatureHeader: string | undefined,
): boolean => {
  const secret = config.paymongo.webhookSecret;
  if (!secret || secret.trim() === '') {
    console.warn('⚠️ PAYMONGO_WEBHOOK_SECRET not set — skipping signature verification (testing only)');
    return true;
  }

  if (!signatureHeader) {
    return false;
  }

  // Format: t=1234567890,v1=abc...,v1=... (multiple v1 possible)
  const parts = signatureHeader.split(',').map((p) => p.trim());
  let timestamp = '';
  const signatures: string[] = [];

  for (const part of parts) {
    if (part.startsWith('t=')) {
      timestamp = part.slice(2);
    } else if (part.startsWith('v1=')) {
      signatures.push(part.slice(3));
    }
  }

  if (!timestamp || signatures.length === 0) {
    return false;
  }

  const payload = rawBody.toString('utf8');
  const signedPayload = `${timestamp}.${payload}`;
  const expected = createHmac('sha256', secret).update(signedPayload).digest('hex');

  return signatures.some((sig) => {
    try {
      const a = Buffer.from(expected, 'hex');
      const b = Buffer.from(sig, 'hex');
      return a.length === b.length && timingSafeEqual(a, b);
    } catch {
      return false;
    }
  });
};

/**
 * Extract SmartSpace order id from PayMongo webhook payload (metadata.order_id).
 */
export const extractOrderIdFromPaymongoEvent = (event: Record<string, unknown>): string | null => {
  const str = JSON.stringify(event);
  const match = /"order_id"\s*:\s*"([^"]+)"/.exec(str);
  return match?.[1] ?? null;
};

/**
 * Collects all numeric `amount` fields from a PayMongo webhook payload.
 * Amounts are in **centavos** (₱1.00 = 100). We return the largest value as pesos,
 * which matches the usual single line-item checkout total.
 */
const collectAmountsCentavos = (obj: unknown, out: number[]): void => {
  if (obj == null) return;
  if (typeof obj === 'object') {
    if (Array.isArray(obj)) {
      for (const item of obj) collectAmountsCentavos(item, out);
    } else {
      for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
        if (k === 'amount' && typeof v === 'number' && Number.isFinite(v)) {
          out.push(v);
        } else {
          collectAmountsCentavos(v, out);
        }
      }
    }
  }
};

/**
 * Best-effort paid amount in **pesos** for webhook reconciliation (down payment vs balance).
 * Returns null if nothing usable was found.
 */
export const extractPaymentAmountPesosFromPaymongoEvent = (event: Record<string, unknown>): number | null => {
  const amounts: number[] = [];
  collectAmountsCentavos(event, amounts);
  if (amounts.length === 0) return null;
  const maxCentavos = Math.max(...amounts);
  if (maxCentavos < 100) return null;
  return maxCentavos / 100;
};
