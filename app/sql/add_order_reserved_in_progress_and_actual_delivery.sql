-- ============================================================================
-- Payment-plan fulfillment: reserved / in_progress statuses + actual delivery
-- ============================================================================

USE smartspace_ar;

ALTER TABLE orders
  MODIFY COLUMN status ENUM(
    'pending',
    'pending_payment_verification',
    'reserved',
    'in_progress',
    'confirmed',
    'shipped',
    'delivered',
    'cancelled',
    'refunded',
    'expired'
  ) DEFAULT 'pending';

ALTER TABLE orders
  ADD COLUMN actual_delivery_at DATETIME NULL DEFAULT NULL
    COMMENT 'Recorded when admin marks order delivered'
    AFTER estimated_delivery_at;
