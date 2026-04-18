import bcrypt from 'bcrypt';
import crypto from 'crypto';
import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import type { AdminRole } from '../auth/admin_role';
import { parseAdminRole } from '../auth/admin_role';
import { Admin } from '../models/admin';
import { generateId } from '../utils/id_generator';
import { assertStrongPassword } from '../utils/password_policy';
import { logAdminActivity } from './admin_activity_log_service';
import { EmailService } from './email_service';

/**
 * Database row structure for admins table.
 * This matches the SQL schema exactly.
 */
type AdminRow = RowDataPacket & {
  readonly id: string;
  readonly email: string;
  readonly password_hash: string;
  readonly full_name: string;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly last_login_at: Date | null;
  readonly email_verified?: number | boolean | null;
  readonly verification_token?: string | null;
  readonly verification_token_expires?: Date | null;
  readonly verification_code?: string | null;
  readonly password_reset_token?: string | null;
  readonly password_reset_expires?: Date | null;
  readonly role?: string | null;
};

let _adminAuthSchemaEnsured = false;

/**
 * Adds email verification + password reset columns to `admins` when missing.
 * Existing rows keep access: new column defaults treat legacy admins as verified.
 */
const ensureAdminAuthSchema = async (): Promise<void> => {
  if (_adminAuthSchemaEnsured) return;
  const pool = getPool();
  const alters: string[] = [
    'ADD COLUMN email_verified TINYINT(1) NOT NULL DEFAULT 1',
    'ADD COLUMN verification_token VARCHAR(255) NULL',
    'ADD COLUMN verification_token_expires DATETIME NULL',
    'ADD COLUMN verification_code VARCHAR(16) NULL',
    'ADD COLUMN password_reset_token VARCHAR(255) NULL',
    'ADD COLUMN password_reset_expires DATETIME NULL',
    `ADD COLUMN role VARCHAR(32) NOT NULL DEFAULT 'super_admin'`,
  ];
  for (const fragment of alters) {
    try {
      await pool.query(`ALTER TABLE admins ${fragment}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (!msg.toLowerCase().includes('duplicate column')) {
        throw e;
      }
    }
  }
  _adminAuthSchemaEnsured = true;
};

const generateAdminVerificationToken = (): string => crypto.randomBytes(32).toString('base64url');

const generateAdminVerificationCode = (): string => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
};

const adminVerificationExpiry = (): Date => {
  const expiration = new Date();
  expiration.setHours(expiration.getHours() + 24);
  return expiration;
};

/**
 * Maps a database row to the Admin model.
 * Excludes password_hash from the response for security.
 */
const mapAdmin = (row: AdminRow): Admin => {
  const ev = row.email_verified;
  const emailVerified = ev === undefined || ev === null ? true : Boolean(ev);
  const roleParsed = parseAdminRole(row.role != null ? String(row.role) : null);
  const role: AdminRole = roleParsed ?? 'super_admin';
  return {
    id: row.id,
    email: row.email,
    fullName: row.full_name,
    createdAt: row.created_at ?? new Date(),
    updatedAt: row.updated_at ?? new Date(),
    lastLoginAt: row.last_login_at ?? null,
    emailVerified,
    role,
  };
};

/**
 * Lists all admins in the system.
 * Returns admins sorted by creation date (newest first).
 */
export const listAdmins = async (): Promise<Admin[]> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const [rows] = await pool.query<AdminRow[]>(
    `SELECT id, email, full_name, created_at, updated_at, last_login_at, email_verified, role
     FROM admins
     ORDER BY created_at DESC`,
  );
  return rows.map(mapAdmin);
};

export const countAdmins = async (): Promise<number> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const [rows] = await pool.query<RowDataPacket[]>(
    'SELECT COUNT(*) AS c FROM admins',
  );
  return Number(rows[0]?.c ?? 0);
};

/**
 * Input interface for creating a new admin.
 * Password is required and will be hashed before storage.
 */
export interface CreateAdminInput {
  readonly email: string;
  readonly password: string;
  readonly fullName: string;
  readonly role: AdminRole;
}

/**
 * Creates a new admin account.
 * 
 * The password is hashed using bcrypt before being stored.
 * Email must be unique - will throw if duplicate.
 */
export const createAdmin = async (input: CreateAdminInput): Promise<Admin> => {
  await ensureAdminAuthSchema();
  assertStrongPassword(input.password);
  const pool = getPool();
  const id = generateId('a'); // 'a' prefix for admin
  const now = new Date();

  // Hash the password with bcrypt (10 rounds is a good default)
  const saltRounds = 10;
  const passwordHash = await bcrypt.hash(input.password.trim(), saltRounds);
  const verificationToken = generateAdminVerificationToken();
  const verificationCode = generateAdminVerificationCode();
  const tokenExpiration = adminVerificationExpiry();

  try {
    await pool.query(
      `INSERT INTO admins (
        id, email, password_hash, full_name, created_at, updated_at,
        email_verified, verification_token, verification_token_expires, verification_code,
        password_reset_token, password_reset_expires, role
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?)`,
      [
        id,
        input.email.toLowerCase().trim(),
        passwordHash,
        input.fullName.trim(),
        now,
        now,
        0,
        verificationToken,
        tokenExpiration,
        verificationCode,
        input.role,
      ],
    );
  } catch (error: unknown) {
    // Check if it's a duplicate email error
    if (error instanceof Error && error.message.includes('Duplicate entry')) {
      throw new Error('An admin with this email already exists');
    }
    throw error;
  }

  const [rows] = await pool.query<AdminRow[]>('SELECT * FROM admins WHERE id = ?', [id]);
  if (rows.length === 0) {
    throw new Error('Failed to create admin');
  }
  await logAdminActivity({
    adminId: id,
    action: 'admin_created',
    entityType: 'admin',
    entityId: id,
    details: { email: input.email.toLowerCase().trim(), role: input.role },
  });

  const created = mapAdmin(rows[0]);
  EmailService.sendAdminVerificationEmail(
    created.fullName,
    created.email,
    verificationToken,
    verificationCode,
  ).catch((err) => console.error('Failed to send admin verification email:', err));

  return created;
};

/**
 * Input interface for updating an admin.
 * 
 * IMPORTANT: This does NOT allow updating email or password.
 * Credentials are immutable for security reasons.
 */
export interface UpdateAdminInput {
  readonly fullName?: string;
  readonly role?: AdminRole;
}

/**
 * Updates an admin's information.
 * 
 * SECURITY: Email and password cannot be updated through this method.
 * This prevents credential changes that could compromise security.
 */
export const updateAdmin = async (adminId: string, input: UpdateAdminInput): Promise<Admin> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const updates: string[] = [];
  const values: unknown[] = [];

  // Only allow updating full name - credentials are protected
  if (input.fullName !== undefined) {
    updates.push('full_name = ?');
    values.push(input.fullName.trim());
  }
  if (input.role !== undefined) {
    updates.push('role = ?');
    values.push(input.role);
  }

  if (updates.length === 0) {
    // No updates requested, just return the current admin
    const [rows] = await pool.query<AdminRow[]>('SELECT * FROM admins WHERE id = ?', [adminId]);
    if (rows.length === 0) {
      throw new Error('Admin not found');
    }
    return mapAdmin(rows[0]);
  }

  // Add updated_at timestamp
  updates.push('updated_at = ?');
  values.push(new Date());
  values.push(adminId);

  await pool.query(
    `UPDATE admins SET ${updates.join(', ')} WHERE id = ?`,
    values,
  );

  const [rows] = await pool.query<AdminRow[]>('SELECT * FROM admins WHERE id = ?', [adminId]);
  if (rows.length === 0) {
    throw new Error('Admin not found');
  }
  await logAdminActivity({
    adminId,
    action: 'admin_profile_updated',
    entityType: 'admin',
    entityId: adminId,
    details: { fullName: input.fullName ?? '' },
  });
  return mapAdmin(rows[0]);
};

/**
 * Finds an admin by their ID.
 * Returns null if not found.
 */
export const findAdminById = async (id: string): Promise<Admin | null> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const [rows] = await pool.query<AdminRow[]>('SELECT * FROM admins WHERE id = ?', [id]);
  if (rows.length === 0) return null;
  return mapAdmin(rows[0]);
};

/**
 * Finds an admin by their email address.
 * Returns null if not found.
 */
export const findAdminByEmail = async (email: string): Promise<Admin | null> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const [rows] = await pool.query<AdminRow[]>(
    'SELECT * FROM admins WHERE email = ?',
    [email.toLowerCase().trim()],
  );
  if (rows.length === 0) return null;
  return mapAdmin(rows[0]);
};

/**
 * Verifies admin credentials (email and password).
 * 
 * Returns the admin if credentials are valid, null otherwise.
 * Also updates the last_login_at timestamp on successful login.
 */
export const verifyAdminCredentials = async (
  email: string,
  password: string,
): Promise<Admin | null> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const [rows] = await pool.query<AdminRow[]>(
    'SELECT * FROM admins WHERE email = ?',
    [email.toLowerCase().trim()],
  );

  if (rows.length === 0) {
    // Admin not found - return null without revealing this
    return null;
  }

  const admin = rows[0];

  // Verify the password using bcrypt
  const passwordMatches = await bcrypt.compare(password, admin.password_hash);

  if (!passwordMatches) {
    // Password doesn't match - return null
    return null;
  }

  const verified = admin.email_verified === undefined || admin.email_verified === null ? true : Boolean(admin.email_verified);
  if (!verified) {
    throw new Error('Please verify your email before signing in.');
  }

  // Update last login timestamp
  await pool.query(
    'UPDATE admins SET last_login_at = ? WHERE id = ?',
    [new Date(), admin.id],
  );

  return mapAdmin(admin);
};

/**
 * Marks an admin email verified (link from email).
 */
export const verifyAdminEmail = async (token: string): Promise<Admin> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const t = token.trim();
  if (!t) {
    throw new Error('Verification token is required');
  }
  const [rows] = await pool.query<AdminRow[]>(
    'SELECT * FROM admins WHERE verification_token = ? AND verification_token_expires > NOW()',
    [t],
  );
  if (rows.length === 0) {
    throw new Error('Invalid or expired verification token');
  }
  const row = rows[0];
  await pool.query(
    `UPDATE admins SET email_verified = TRUE, verification_token = NULL, verification_token_expires = NULL,
     verification_code = NULL, updated_at = NOW() WHERE id = ?`,
    [row.id],
  );
  const updated = await findAdminById(row.id);
  if (!updated) {
    throw new Error('Failed to verify admin email');
  }
  return updated;
};

/**
 * Verifies admin email using the 6-character code (same alphabet as customer signup).
 */
export const verifyAdminEmailByCode = async (code: string): Promise<Admin> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const c = code.trim().toUpperCase();
  if (!c) {
    throw new Error('Verification code is required');
  }
  const [rows] = await pool.query<AdminRow[]>(
    'SELECT * FROM admins WHERE verification_code = ? AND verification_token_expires > NOW()',
    [c],
  );
  if (rows.length === 0) {
    throw new Error('Invalid or expired verification code');
  }
  const row = rows[0];
  await pool.query(
    `UPDATE admins SET email_verified = TRUE, verification_token = NULL, verification_token_expires = NULL,
     verification_code = NULL, updated_at = NOW() WHERE id = ?`,
    [row.id],
  );
  const updated = await findAdminById(row.id);
  if (!updated) {
    throw new Error('Failed to verify admin email');
  }
  return updated;
};

export const resendAdminVerificationEmail = async (adminId: string): Promise<void> => {
  await ensureAdminAuthSchema();
  const pool = getPool();
  const admin = await findAdminById(adminId);
  if (!admin) {
    throw new Error('Admin not found');
  }
  if (admin.emailVerified) {
    throw new Error('This account is already verified');
  }
  const verificationToken = generateAdminVerificationToken();
  const verificationCode = generateAdminVerificationCode();
  const tokenExpiration = adminVerificationExpiry();
  await pool.query(
    `UPDATE admins SET verification_token = ?, verification_token_expires = ?, verification_code = ?, updated_at = NOW()
     WHERE id = ?`,
    [verificationToken, tokenExpiration, verificationCode, adminId],
  );
  await EmailService.sendAdminVerificationEmail(
    admin.fullName,
    admin.email,
    verificationToken,
    verificationCode,
  );
};

export const FORGOT_PASSWORD_ACK =
  'If an account exists for this email, you will receive password reset instructions.';

/**
 * Creates a short-lived password reset token and emails the admin.
 * Always completes without error (no email enumeration).
 */
export const requestAdminPasswordReset = async (emailRaw: string): Promise<void> => {
  await ensureAdminAuthSchema();
  const email = emailRaw.trim().toLowerCase();
  if (!email) {
    return;
  }
  const pool = getPool();
  const [rows] = await pool.query<AdminRow[]>(
    'SELECT * FROM admins WHERE email = ? LIMIT 1',
    [email],
  );
  if (rows.length === 0) {
    return;
  }
  const row = rows[0];
  const token = crypto.randomBytes(32).toString('base64url');
  const exp = new Date();
  exp.setHours(exp.getHours() + 1);
  await pool.query(
    `UPDATE admins SET password_reset_token = ?, password_reset_expires = ?, updated_at = NOW() WHERE id = ?`,
    [token, exp, row.id],
  );
  const { config } = await import('../config/env');
  const base = config.frontend.url.replace(/\/$/, '');
  const resetLink = `${base}/#/admin/reset-password?token=${encodeURIComponent(token)}`;
  await EmailService.sendAdminPasswordResetEmail(row.full_name, row.email, resetLink);
};

export const resetAdminPasswordWithToken = async (token: string, newPassword: string): Promise<void> => {
  await ensureAdminAuthSchema();
  assertStrongPassword(newPassword);
  const pool = getPool();
  const t = token.trim();
  if (!t) {
    throw new Error('Reset token is required');
  }
  const [rows] = await pool.query<AdminRow[]>(
    'SELECT id FROM admins WHERE password_reset_token = ? AND password_reset_expires > NOW() LIMIT 1',
    [t],
  );
  if (rows.length === 0) {
    throw new Error('Invalid or expired reset link. Request a new one.');
  }
  const id = rows[0].id;
  const hash = await bcrypt.hash(newPassword.trim(), 10);
  await pool.query(
    `UPDATE admins SET password_hash = ?, password_reset_token = NULL, password_reset_expires = NULL, updated_at = NOW() WHERE id = ?`,
    [hash, id],
  );
};































