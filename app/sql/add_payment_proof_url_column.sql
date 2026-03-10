-- ============================================================================
-- Add payment_proof_url column to orders table
-- ----------------------------------------------------------------------------
-- This script adds a payment_proof_url column to store the URL of uploaded
-- payment proof screenshots for verification.
-- ============================================================================

USE smartspace_ar;

-- Add payment_proof_url column to store the URL of payment proof images
ALTER TABLE orders
  ADD COLUMN payment_proof_url VARCHAR(500) NULL AFTER payment_status;

-- Add index for faster queries on payment verification
CREATE INDEX idx_orders_payment_status ON orders(payment_status);

-- Update existing orders with pending_payment_verification status
-- (if any exist, this ensures they're properly tracked)




















