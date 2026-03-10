-- ============================================================================
-- Add missing columns to reviews table
-- ----------------------------------------------------------------------------
-- This script adds the product_name and user_name columns that the backend
-- expects but weren't in the original schema.
-- ============================================================================

USE smartspace_ar;

-- Add product_name column (denormalized product name for quick display)
ALTER TABLE reviews
  ADD COLUMN product_name VARCHAR(255) NOT NULL DEFAULT '' AFTER product_id;

-- Add user_name column (denormalized user name for quick display)
ALTER TABLE reviews
  ADD COLUMN user_name VARCHAR(150) NOT NULL DEFAULT '' AFTER user_id;

-- Update existing review with proper values (if you have sample data)
UPDATE reviews r
INNER JOIN products p ON r.product_id = p.id
SET r.product_name = p.name
WHERE r.product_name = '';

UPDATE reviews r
INNER JOIN users u ON r.user_id = u.id
SET r.user_name = u.full_name
WHERE r.user_name = '';

-- Remove the default values now that existing data is populated
ALTER TABLE reviews
  MODIFY COLUMN product_name VARCHAR(255) NOT NULL,
  MODIFY COLUMN user_name VARCHAR(150) NOT NULL;
























