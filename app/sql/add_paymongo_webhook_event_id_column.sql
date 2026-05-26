-- ============================================================================
-- Add explicit PayMongo webhook idempotency column on orders
-- ----------------------------------------------------------------------------
-- Why:
-- - Webhook retries can send the same PayMongo event more than once.
-- - We must record the last processed event id on the order row itself,
--   independent from invoice tables, to keep idempotency reliable.
-- - This avoids misusing payment_proof_url (which must stay an image URL).
-- ============================================================================

USE smartspace_ar;

ALTER TABLE orders
  ADD COLUMN last_paymongo_event_id VARCHAR(191) NULL DEFAULT NULL
  COMMENT 'Last processed PayMongo webhook event id'
  AFTER payment_proof_url;

CREATE INDEX idx_orders_last_paymongo_event_id
  ON orders(last_paymongo_event_id);

