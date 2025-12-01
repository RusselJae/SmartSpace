/**
 * Admin model representing an administrator in the SmartSpace system.
 * 
 * Admins have full access to the admin console and can manage
 * products, orders, reviews, users, and other admins.
 */
export interface Admin {
  readonly id: string;
  readonly email: string;
  readonly fullName: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
  readonly lastLoginAt: Date | null;
  // Note: password_hash is never exposed in the API response
}




