-- Run once on MySQL. Adds PayMongo plan + valid ID + payment_status for down-payment flow.

-- Optional: extend payment_status for first tranche received (balance still due)
ALTER TABLE orders
  MODIFY COLUMN payment_status ENUM(
    'pending',
    'completed',
    'failed',
    'refunded',
    'downpayment_received'
  ) DEFAULT 'pending';

ALTER TABLE orders
  ADD COLUMN payment_plan VARCHAR(32) NULL DEFAULT NULL COMMENT 'full | downpayment' AFTER payment_method;

ALTER TABLE orders
  ADD COLUMN valid_id_proof_url VARCHAR(1024) NULL DEFAULT NULL AFTER payment_proof_url;
