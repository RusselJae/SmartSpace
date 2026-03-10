import bcrypt from 'bcrypt';
import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { Admin } from '../models/admin';
import { generateId } from '../utils/id_generator';

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
};

/**
 * Maps a database row to the Admin model.
 * Excludes password_hash from the response for security.
 */
const mapAdmin = (row: AdminRow): Admin => {
  return {
    id: row.id,
    email: row.email,
    fullName: row.full_name,
    createdAt: row.created_at ?? new Date(),
    updatedAt: row.updated_at ?? new Date(),
    lastLoginAt: row.last_login_at ?? null,
  };
};

/**
 * Lists all admins in the system.
 * Returns admins sorted by creation date (newest first).
 */
export const listAdmins = async (): Promise<Admin[]> => {
  const pool = getPool();
  const [rows] = await pool.query<AdminRow[]>(
    `SELECT id, email, full_name, created_at, updated_at, last_login_at
     FROM admins
     ORDER BY created_at DESC`,
  );
  return rows.map(mapAdmin);
};

/**
 * Input interface for creating a new admin.
 * Password is required and will be hashed before storage.
 */
export interface CreateAdminInput {
  readonly email: string;
  readonly password: string;
  readonly fullName: string;
}

/**
 * Creates a new admin account.
 * 
 * The password is hashed using bcrypt before being stored.
 * Email must be unique - will throw if duplicate.
 */
export const createAdmin = async (input: CreateAdminInput): Promise<Admin> => {
  const pool = getPool();
  const id = generateId('a'); // 'a' prefix for admin
  const now = new Date();

  // Hash the password with bcrypt (10 rounds is a good default)
  const saltRounds = 10;
  const passwordHash = await bcrypt.hash(input.password, saltRounds);

  try {
    await pool.query(
      `INSERT INTO admins (
        id, email, password_hash, full_name, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)`,
      [id, input.email.toLowerCase().trim(), passwordHash, input.fullName.trim(), now, now],
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
  return mapAdmin(rows[0]);
};

/**
 * Input interface for updating an admin.
 * 
 * IMPORTANT: This does NOT allow updating email or password.
 * Credentials are immutable for security reasons.
 */
export interface UpdateAdminInput {
  readonly fullName?: string;
}

/**
 * Updates an admin's information.
 * 
 * SECURITY: Email and password cannot be updated through this method.
 * This prevents credential changes that could compromise security.
 */
export const updateAdmin = async (adminId: string, input: UpdateAdminInput): Promise<Admin> => {
  const pool = getPool();
  const updates: string[] = [];
  const values: unknown[] = [];

  // Only allow updating full name - credentials are protected
  if (input.fullName !== undefined) {
    updates.push('full_name = ?');
    values.push(input.fullName.trim());
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
  return mapAdmin(rows[0]);
};

/**
 * Finds an admin by their ID.
 * Returns null if not found.
 */
export const findAdminById = async (id: string): Promise<Admin | null> => {
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

  // Update last login timestamp
  await pool.query(
    'UPDATE admins SET last_login_at = ? WHERE id = ?',
    [new Date(), admin.id],
  );

  return mapAdmin(admin);
};































