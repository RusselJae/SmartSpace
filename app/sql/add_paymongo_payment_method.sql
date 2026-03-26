-- Add PayMongo as a payment_method value (run once on your MySQL DB).
-- If your column is already VARCHAR, this migration may not be needed.

ALTER TABLE orders
  MODIFY COLUMN payment_method ENUM('card','paypal','cod','gcash','paymongo')
  NOT NULL;
