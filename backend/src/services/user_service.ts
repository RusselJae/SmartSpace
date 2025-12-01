import { RowDataPacket } from 'mysql2';
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
  };
};

export const listUsers = async (): Promise<User[]> => {
  const pool = getPool();
  const [rows] = await pool.query<UserRow[]>(
    `SELECT id, email, full_name, username, gender, date_of_birth, avatar_url, phone_number, created_at, updated_at, last_login_at
     FROM users
     ORDER BY created_at DESC`,
  );
  return rows.map(mapUser);
};

export interface CreateUserInput {
  readonly email: string;
  readonly fullName: string;
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

export const createUser = async (input: CreateUserInput): Promise<User> => {
  const pool = getPool();
  const id = generateId('u');
  const now = new Date();
  const username = deriveUsername(input, id);

  await pool.query(
    `INSERT INTO users (
      id, email, password_hash, full_name, username, gender, date_of_birth, avatar_url,
      phone_number, created_at, updated_at, last_login_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      input.email,
      null,
      input.fullName,
      username,
      input.gender ?? null,
      null,
      null,
      input.phoneNumber ?? null,
      now,
      now,
      now,
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

