-- Add email verification fields to users table
-- This migration adds support for email verification during signup

ALTER TABLE users
ADD COLUMN email_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN verification_token VARCHAR(255) NULL,
ADD COLUMN verification_token_expires TIMESTAMP NULL,
ADD INDEX idx_verification_token (verification_token);













