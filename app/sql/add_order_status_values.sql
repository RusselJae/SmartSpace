-- ============================================================================
-- Add missing status values to orders table
-- ----------------------------------------------------------------------------
-- This script adds 'pending_payment_verification' and 'expired' to the 
-- status ENUM to support payment proof upload workflow and expired orders.
-- ============================================================================

USE smartspace_ar;

-- Update status enum to include 'pending_payment_verification' and 'expired'
-- Note: MySQL doesn't support direct enum modification, so we need to alter the column
ALTER TABLE orders
  MODIFY COLUMN status ENUM(
    'pending',
    'pending_payment_verification',
    'confirmed',
    'shipped',
    'delivered',
    'cancelled',
    'refunded',
    'expired'
  ) DEFAULT 'pending';






