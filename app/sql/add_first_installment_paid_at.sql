-- Run once on MySQL. Anchors the 3-month 0% / no-daily-fee window to the first PayMongo payment.
-- (Down payment confirmed = first tranche cleared.)

ALTER TABLE orders
  ADD COLUMN first_installment_paid_at DATETIME NULL DEFAULT NULL
  COMMENT 'When first PayMongo tranche (down payment) was recorded; 3-month policy window starts here';
