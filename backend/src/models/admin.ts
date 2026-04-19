/**
 * Admin model representing an administrator in the SmartSpace system.
 * 
 * Admins have full access to the admin console and can manage
 * products, orders, reviews, users, and other admins.
 */
import type { AdminRole } from '../auth/admin_role';

export interface Admin {
  readonly id: string;
  readonly email: string;
  readonly fullName: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
  readonly lastLoginAt: Date | null;
  /** False until the admin completes email verification (new accounts). */
  readonly emailVerified: boolean;
  readonly role: AdminRole;
  /** When true, login and API access are blocked until re-enabled by a super admin. */
  readonly isDisabled: boolean;
  /** Permissions granted beyond the role baseline. */
  readonly extraPermissions: readonly string[];
  /** Permissions removed from the effective set (overrides role / extras). */
  readonly revokedPermissions: readonly string[];
  // Note: password_hash is never exposed in the API response
}































