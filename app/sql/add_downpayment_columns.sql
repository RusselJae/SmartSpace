-- ============================================================================
-- Add downpayment columns to orders table for GCash payment tracking
-- ----------------------------------------------------------------------------
-- This script adds downpayment_amount and remaining_balance columns to track
-- GCash downpayments (20% of total) for security and verification purposes.
-- Also updates payment_method enum to include 'gcash'.
-- ============================================================================

USE smartspace_ar;

-- First, update the payment_method enum to include 'gcash'
-- Note: MySQL doesn't support direct enum modification, so we need to alter the column
ALTER TABLE orders
  MODIFY COLUMN payment_method ENUM('card','paypal','cod','gcash') NOT NULL;

-- Update payment_status enum to include 'downpayment_paid' for COD orders
ALTER TABLE orders
  MODIFY COLUMN payment_status ENUM('pending','completed','failed','refunded','downpayment_paid') DEFAULT 'pending';

-- Add downpayment_amount column (20% of total for GCash orders)
ALTER TABLE orders
  ADD COLUMN downpayment_amount DECIMAL(10,2) DEFAULT 0.00 AFTER total_amount;

-- Add remaining_balance column (80% of total for GCash orders, full amount for COD)
ALTER TABLE orders
  ADD COLUMN remaining_balance DECIMAL(10,2) DEFAULT 0.00 AFTER downpayment_amount;

-- Update existing orders: set remaining_balance = total_amount for COD orders
-- and calculate downpayment for any existing GCash orders (if any)
UPDATE orders
SET remaining_balance = total_amount
WHERE payment_method = 'cod' AND remaining_balance = 0.00;

-- For any existing GCash orders (if any), calculate downpayment and remaining balance
UPDATE orders
SET 
  downpayment_amount = total_amount * 0.20,
  remaining_balance = total_amount * 0.80
WHERE payment_method = 'gcash' AND downpayment_amount = 0.00;

