import { RowDataPacket } from 'mysql2';
import crypto from 'crypto';
import bcrypt from 'bcrypt';
import { getPool } from '../config/database';
import { User } from '../models/user';
import { generateId } from '../utils/id_generator';

type UserRow = RowDataPacket & {
  readonly id: string;
  readonly email: string;
  readonly full_name: string;
  readonly username: string;
  readonly gender: 'male' | 'female' | 'other' | null;
  readonly date_of_birth: Date | null;
  readonly avatar_url: string | null;
  readonly phone_number: string | null;
  readonly created_at: Date;
  readonly updated_at: Date | null;
  readonly last_login_at: Date | null;
  readonly email_verified: boolean;
  readonly verification_token: string | null;
  readonly verification_token_expires: Date | null;
  readonly verification_code: string | null;
};

const mapUser = (row: UserRow): User => {
  return {
    id: row.id,
    email: row.email,
    fullName: row.full_name,
    username: row.username,
    phoneNumber: row.phone_number ?? undefined,
    gender: row.gender ?? undefined,
    dateOfBirth: row.date_of_birth ?? undefined,
    avatarUrl: row.avatar_url ?? undefined,
    addresses: [],
    wishlistProductIds: [],
    orderIds: [],
    preferredStyle: '',
    minBudget: 0,
    maxBudget: 0,
    createdAt: row.created_at ?? new Date(),
    lastLoginAt: row.last_login_at ?? row.created_at ?? new Date(),
    emailVerified: row.email_verified ?? false,
    verificationToken: row.verification_token ?? undefined,
    verificationTokenExpires: row.verification_token_expires ?? undefined,
    verificationCode: row.verification_code ?? undefined,
  };
};

export const listUsers = async (): Promise<User[]> => {
  const pool = getPool();
  const [rows] = await pool.query<UserRow[]>(
    `SELECT id, email, full_name, username, gender, date_of_birth, avatar_url, phone_number, 
            created_at, updated_at, last_login_at, email_verified, verification_token, verification_token_expires, verification_code
     FROM users
     ORDER BY created_at DESC`,
  );
  return rows.map(mapUser);
};

export interface CreateUserInput {
  readonly email: string;
  readonly fullName: string;
  readonly password: string;
  readonly username?: string;
  readonly phoneNumber?: string;
  readonly gender?: 'male' | 'female' | 'other';
}

const deriveUsername = (input: CreateUserInput, fallbackId: string): string => {
  const source = (input.username ?? input.fullName).trim();
  if (source.length > 0) {
    const sanitized = source.toLowerCase().replace(/[^a-z0-9]+/g, '');
    if (sanitized.length > 0) {
      return sanitized.length > 3 ? sanitized : `${sanitized}${fallbackId.slice(-4)}`;
    }
  }
  const emailPrefix = input.email.split('@')[0].replace(/[^a-z0-9]+/g, '');
  if (emailPrefix.length >= 3) {
    return emailPrefix.toLowerCase();
  }
  return `user_${fallbackId.slice(-6)}`;
};

/**
 * Generates a secure random verification token for email verification.
 * The token is a URL-safe base64 string that's cryptographically random.
 */
const generateVerificationToken = (): string => {
  return crypto.randomBytes(32).toString('base64url');
};

/**
 * Generates a short, user-friendly verification code (6 characters).
 * Uses uppercase letters and numbers, excluding confusing characters (0, O, I, 1).
 */
const generateVerificationCode = (): string => {
  // Use characters that are easy to distinguish: A-Z (excluding I, O) and 2-9 (excluding 0, 1)
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
};

/**
 * Calculates the expiration date for a verification token.
 * Tokens expire after 24 hours from generation.
 */
const getTokenExpiration = (): Date => {
  const expiration = new Date();
  expiration.setHours(expiration.getHours() + 24);
  return expiration;
};

export const createUser = async (input: CreateUserInput): Promise<User> => {
  const pool = getPool();
  const id = generateId('u');
  const now = new Date();
  const username = deriveUsername(input, id);
  
  // Keep password rules centralized here so both API and any internal callers
  // behave consistently. (This app currently uses a username/email + password login.)
  const password = input.password?.trim() ?? '';
  if (password.length < 6) {
    throw new Error('Password must be at least 6 characters long');
  }

  // bcrypt with 10 rounds is a sensible default for interactive logins.
  const passwordHash = await bcrypt.hash(password, 10);

  // Generate verification token, code, and expiration date
  // New users start with email_verified = false and need to verify via email
  const verificationToken = generateVerificationToken();
  const verificationCode = generateVerificationCode();
  const tokenExpiration = getTokenExpiration();

  await pool.query(
    `INSERT INTO users (
      id, email, password_hash, full_name, username, gender, date_of_birth, avatar_url,
      phone_number, created_at, updated_at, last_login_at, email_verified, verification_token, verification_token_expires, verification_code
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      input.email,
      passwordHash,
      input.fullName,
      username,
      input.gender ?? null,
      null,
      null,
      input.phoneNumber ?? null,
      now,
      now,
      now,
      false, // email_verified starts as false
      verificationToken,
      tokenExpiration,
      verificationCode,
    ],
  );

  const [rows] = await pool.query<UserRow[]>('SELECT * FROM users WHERE id = ?', [id]);
  if (rows.length === 0) {
    throw new Error('Failed to create user');
  }
  return mapUser(rows[0]);
};

export interface UpdateUserInput {
  readonly fullName?: string;
  readonly username?: string;
  readonly phoneNumber?: string;
  readonly gender?: 'male' | 'female' | 'other' | null;
  readonly dateOfBirth?: Date | null;
  readonly avatarUrl?: string | null;
}

export const updateUser = async (userId: string, input: UpdateUserInput): Promise<User> => {
  const pool = getPool();
  const updates: string[] = [];
  const values: unknown[] = [];

  if (input.fullName !== undefined) {
    updates.push('full_name = ?');
    values.push(input.fullName);
  }
  if (input.username !== undefined) {
    updates.push('username = ?');
    values.push(input.username);
  }
  if (input.phoneNumber !== undefined) {
    updates.push('phone_number = ?');
    values.push(input.phoneNumber);
  }
  if (input.gender !== undefined) {
    updates.push('gender = ?');
    values.push(input.gender);
  }
  if (input.dateOfBirth !== undefined) {
    updates.push('date_of_birth = ?');
    values.push(input.dateOfBirth);
  }
  if (input.avatarUrl !== undefined) {
    updates.push('avatar_url = ?');
    values.push(input.avatarUrl);
  }

  if (updates.length === 0) {
    const [rows] = await pool.query<UserRow[]>('SELECT * FROM users WHERE id = ?', [userId]);
    if (rows.length === 0) {
      throw new Error('User not found');
    }
    return mapUser(rows[0]);
  }

  updates.push('updated_at = ?');
  values.push(new Date());
  values.push(userId);

  await pool.query(
    `UPDATE users SET ${updates.join(', ')} WHERE id = ?`,
    values,
  );

  const [rows] = await pool.query<UserRow[]>('SELECT * FROM users WHERE id = ?', [userId]);
  if (rows.length === 0) {
    throw new Error('User not found');
  }
  return mapUser(rows[0]);
};

export const findUserById = async (id: string): Promise<User | null> => {
  const pool = getPool();
  const [rows] = await pool.query<UserRow[]>('SELECT * FROM users WHERE id = ?', [id]);
  if (rows.length === 0) return null;
  return mapUser(rows[0]);
};

type UserAuthRow = RowDataPacket & {
  readonly id: string;
  readonly email: string;
  readonly username: string;
  readonly password_hash: string | null;
  readonly email_verified: boolean;
  readonly last_login_at: Date | null;
};

/**
 * Verifies a user's credentials (email/username + password).
 *
 * Returns the public user object on success; throws on failure.
 * This is used by the API login route so the Flutter app never needs to
 * download the full user list just to authenticate.
 */
export const verifyUserCredentials = async (
  identifier: string,
  password: string,
): Promise<User> => {
  const pool = getPool();
  const normalized = identifier.trim().toLowerCase();

  if (normalized.length === 0 || password.trim().length === 0) {
    throw new Error('Email/username and password are required');
  }

  const [rows] = await pool.query<UserAuthRow[]>(
    `SELECT id, email, username, password_hash, email_verified, last_login_at
     FROM users
     WHERE LOWER(email) = ? OR LOWER(username) = ?
     LIMIT 1`,
    [normalized, normalized],
  );

  if (rows.length === 0) {
    throw new Error('Invalid username or password');
  }

  const row = rows[0];
  if (!row.email_verified) {
    throw new Error('Please verify your email address before signing in.');
  }

  if (!row.password_hash) {
    // This protects older accounts created before password hashing existed.
    throw new Error('This account does not have a password set. Please create a new account or contact support.');
  }

  const ok = await bcrypt.compare(password, row.password_hash);
  if (!ok) {
    throw new Error('Invalid username or password');
  }

  await pool.query('UPDATE users SET last_login_at = NOW(), updated_at = NOW() WHERE id = ?', [row.id]);

  const user = await findUserById(row.id);
  if (!user) {
    throw new Error('User not found');
  }
  return user;
};

/**
 * Changes a user's password after verifying their current password.
 */
export const changeUserPassword = async (
  userId: string,
  currentPassword: string,
  newPassword: string,
): Promise<void> => {
  const pool = getPool();

  const current = (currentPassword ?? '').trim();
  const next = (newPassword ?? '').trim();

  if (current.length === 0 || next.length === 0) {
    throw new Error('Current password and new password are required');
  }
  if (next.length < 6) {
    throw new Error('New password must be at least 6 characters long');
  }
  if (current === next) {
    throw new Error('New password must be different from the current password');
  }

  const [rows] = await pool.query<UserAuthRow[]>(
    `SELECT id, password_hash
     FROM users
     WHERE id = ?
     LIMIT 1`,
    [userId],
  );
  if (rows.length === 0) {
    throw new Error('User not found');
  }

  const row = rows[0];
  if (!row.password_hash) {
    throw new Error('This account does not have a password set.');
  }

  const ok = await bcrypt.compare(current, row.password_hash);
  if (!ok) {
    throw new Error('Current password is incorrect');
  }

  const newHash = await bcrypt.hash(next, 10);
  await pool.query(
    'UPDATE users SET password_hash = ?, updated_at = NOW() WHERE id = ?',
    [newHash, userId],
  );
};

/**
 * Finds a user by their verification token.
 * Used during email verification flow when user clicks the verification link.
 */
export const findUserByVerificationToken = async (token: string): Promise<User | null> => {
  const pool = getPool();
  const [rows] = await pool.query<UserRow[]>(
    'SELECT * FROM users WHERE verification_token = ? AND verification_token_expires > NOW()',
    [token],
  );
  if (rows.length === 0) return null;
  return mapUser(rows[0]);
};

/**
 * Finds a user by their verification code.
 * Used when user manually enters the verification code.
 */
export const findUserByVerificationCode = async (code: string): Promise<User | null> => {
  const pool = getPool();
  const [rows] = await pool.query<UserRow[]>(
    'SELECT * FROM users WHERE verification_code = ? AND verification_token_expires > NOW()',
    [code.toUpperCase()],
  );
  if (rows.length === 0) return null;
  return mapUser(rows[0]);
};

/**
 * Verifies a user's email address by token.
 * Marks the email as verified and clears the verification token and code.
 */
export const verifyUserEmail = async (token: string): Promise<User> => {
  const pool = getPool();
  
  // Find user by token and check expiration
  const user = await findUserByVerificationToken(token);
  if (!user) {
    throw new Error('Invalid or expired verification token');
  }

  // Update user to mark email as verified and clear token and code
  await pool.query(
    `UPDATE users 
     SET email_verified = TRUE, 
         verification_token = NULL, 
         verification_token_expires = NULL,
         verification_code = NULL,
         updated_at = NOW()
     WHERE id = ?`,
    [user.id],
  );

  // Return updated user
  const updatedUser = await findUserById(user.id);
  if (!updatedUser) {
    throw new Error('Failed to verify email');
  }
  return updatedUser;
};

/**
 * Verifies a user's email address by code.
 * Marks the email as verified and clears the verification token and code.
 */
export const verifyUserEmailByCode = async (code: string): Promise<User> => {
  const pool = getPool();
  
  // Find user by code and check expiration (case-insensitive)
  const user = await findUserByVerificationCode(code.toUpperCase());
  if (!user) {
    throw new Error('Invalid or expired verification code');
  }

  // Update user to mark email as verified and clear token and code
  await pool.query(
    `UPDATE users 
     SET email_verified = TRUE, 
         verification_token = NULL, 
         verification_token_expires = NULL,
         verification_code = NULL,
         updated_at = NOW()
     WHERE id = ?`,
    [user.id],
  );

  // Return updated user
  const updatedUser = await findUserById(user.id);
  if (!updatedUser) {
    throw new Error('Failed to verify email');
  }
  return updatedUser;
};

/**
 * Resends verification email by generating a new token and code.
 * Useful when user requests a new verification email.
 */
export const resendVerificationToken = async (userId: string): Promise<{ token: string; code: string }> => {
  const pool = getPool();
  const newToken = generateVerificationToken();
  const newCode = generateVerificationCode();
  const tokenExpiration = getTokenExpiration();

  await pool.query(
    `UPDATE users 
     SET verification_token = ?, 
         verification_token_expires = ?,
         verification_code = ?,
         updated_at = NOW()
     WHERE id = ?`,
    [newToken, tokenExpiration, newCode, userId],
  );

  return { token: newToken, code: newCode };
};

/**
 * Deletes unverified user accounts that were created more than 5 minutes ago.
 * This cleanup function helps maintain database hygiene by removing accounts
 * that users never verified, preventing accumulation of unverified accounts.
 * 
 * Foreign key constraints with ON DELETE CASCADE will automatically clean up
 * related records in user_addresses, orders, reviews, and wishlist_items tables.
 * 
 * @returns The number of users deleted
 */
export const deleteUnverifiedUsers = async (): Promise<number> => {
  const pool = getPool();
  
  // Delete users where:
  // - email_verified is false
  // - created_at is more than 5 minutes ago
  // This uses MySQL's DATE_SUB function to calculate 5 minutes ago
  const [result] = await pool.query(
    `DELETE FROM users 
     WHERE email_verified = FALSE 
       AND created_at < DATE_SUB(NOW(), INTERVAL 5 MINUTE)`
  );
  
  // MySQL2 returns result as [ResultSetHeader, FieldPacket[]]
  // ResultSetHeader has affectedRows property
  const affectedRows = (result as any).affectedRows ?? 0;
  return affectedRows;
};