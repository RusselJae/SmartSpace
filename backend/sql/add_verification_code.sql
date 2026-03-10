-- Add verification code field to users table
-- This allows users to verify their email by entering a short code instead of clicking a link

ALTER TABLE users
ADD COLUMN verification_code VARCHAR(8) NULL,
ADD INDEX idx_verification_code (verification_code);












