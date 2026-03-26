-- Run once. Checkout option (layaway vs hulugan) + delivery estimate after admin confirms.

ALTER TABLE orders
  ADD COLUMN order_option VARCHAR(32) NULL DEFAULT NULL
  COMMENT 'layaway | hulugan';

ALTER TABLE orders
  ADD COLUMN estimated_delivery_at DATETIME NULL DEFAULT NULL
  COMMENT 'Set when status becomes confirmed (+10–12 days)';
