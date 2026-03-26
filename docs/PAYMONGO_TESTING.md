# PayMongo (test / sandbox)

## 1. Database

Run once:

```sql
-- app/sql/add_paymongo_payment_method.sql
ALTER TABLE orders
  MODIFY COLUMN payment_method ENUM('card','paypal','cod','gcash','paymongo')
  NOT NULL;
```

If your `payment_method` column differs, adjust the enum list to match your schema and add `paymongo`.

## 2. Backend `.env`

Copy from `backend/.env.example`:

```env
PAYMONGO_SECRET_KEY=sk_test_xxxxxxxx
# Optional locally — webhook signature verification skipped if empty
PAYMONGO_WEBHOOK_SECRET=
PUBLIC_API_BASE_URL=http://localhost:4000
```

Use **test** secret keys from the [PayMongo dashboard](https://dashboard.paymongo.com).

## 3. Webhooks (optional for full flow)

PayMongo cannot POST to `localhost`. For automatic order confirmation:

1. Expose the API with **ngrok** (or similar): `https://xxxx.ngrok.io`
2. In PayMongo → Webhooks, set URL: `https://xxxx.ngrok.io/api/webhooks/paymongo`
3. Set `PAYMONGO_WEBHOOK_SECRET` to the signing secret from the dashboard

Without a webhook, the order stays `pending` until you confirm manually in admin (if you add that) or you verify payment in the PayMongo dashboard and update the DB.

## 4. App flow

1. Checkout → choose **PayMongo (Test)** → Place Order  
2. Backend creates a Checkout Session → app opens `checkout_url` in the browser  
3. Pay using PayMongo test cards / GCash test flow  
4. On success, PayMongo redirects to `PAYMONGO_SUCCESS_URL` (default: `{PUBLIC_API_BASE_URL}/api/paymongo-return/success`)  
5. Webhook `checkout_session.payment.paid` → order `confirmed`, `payment_status` = `completed`

## 5. Going live

- Replace `sk_test_...` with `sk_live_...`  
- Set `PAYMONGO_WEBHOOK_SECRET` and a public HTTPS webhook URL  
- Tighten CORS / origin rules in `app.ts` for production  
