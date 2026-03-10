import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';

export interface Address {
  readonly id: string;
  readonly userId: string;
  readonly fullName: string;
  readonly phoneNumber: string;
  readonly region: string;
  readonly postalCode: string;
  readonly street: string;
  readonly label: 'Home' | 'Work' | 'Other';
  readonly isDefault: boolean;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

type AddressRow = RowDataPacket & {
  readonly id: string;
  readonly user_id: string;
  readonly full_name: string;
  readonly phone_number: string;
  readonly region: string;
  readonly postal_code: string | null;
  readonly street: string;
  readonly label: 'Home' | 'Work' | 'Other';
  readonly is_default: boolean;
  readonly created_at: Date;
  readonly updated_at: Date;
};

const mapAddress = (row: AddressRow): Address => {
  return {
    id: row.id,
    userId: row.user_id,
    fullName: row.full_name,
    phoneNumber: row.phone_number,
    region: row.region,
    postalCode: row.postal_code ?? '',
    street: row.street,
    label: row.label,
    isDefault: Boolean(row.is_default),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
};

export const listAddressesByUser = async (userId: string): Promise<Address[]> => {
  const pool = getPool();
  const [rows] = await pool.query<AddressRow[]>(
    `SELECT * FROM user_addresses WHERE user_id = ? ORDER BY is_default DESC, created_at DESC`,
    [userId],
  );
  return rows.map(mapAddress);
};

export interface CreateAddressInput {
  readonly userId: string;
  readonly fullName: string;
  readonly phoneNumber: string;
  readonly region: string;
  readonly postalCode?: string;
  readonly street: string;
  readonly label?: 'Home' | 'Work' | 'Other';
  readonly isDefault?: boolean;
}

export const createAddress = async (input: CreateAddressInput): Promise<Address> => {
  const pool = getPool();
  const id = generateId('addr');
  const label = input.label ?? 'Home';
  
  // If this is set as default, unset other defaults for this user
  if (input.isDefault) {
    await pool.query('UPDATE user_addresses SET is_default = FALSE WHERE user_id = ?', [input.userId]);
  }
  
  await pool.query(
    `INSERT INTO user_addresses (id, user_id, full_name, phone_number, region, postal_code, street, label, is_default, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`,
    [id, input.userId, input.fullName, input.phoneNumber, input.region, input.postalCode ?? null, input.street, label, input.isDefault ?? false],
  );

  const [rows] = await pool.query<AddressRow[]>('SELECT * FROM user_addresses WHERE id = ?', [id]);
  if (rows.length === 0) {
    throw new Error('Failed to create address');
  }
  return mapAddress(rows[0]);
};

export interface UpdateAddressInput {
  readonly fullName?: string;
  readonly phoneNumber?: string;
  readonly region?: string;
  readonly postalCode?: string;
  readonly street?: string;
  readonly label?: 'Home' | 'Work' | 'Other';
  readonly isDefault?: boolean;
}

export const updateAddress = async (addressId: string, userId: string, input: UpdateAddressInput): Promise<Address> => {
  const pool = getPool();
  const updates: string[] = [];
  const values: unknown[] = [];

  if (input.fullName !== undefined) {
    updates.push('full_name = ?');
    values.push(input.fullName);
  }
  if (input.phoneNumber !== undefined) {
    updates.push('phone_number = ?');
    values.push(input.phoneNumber);
  }
  if (input.region !== undefined) {
    updates.push('region = ?');
    values.push(input.region);
  }
  if (input.postalCode !== undefined) {
    updates.push('postal_code = ?');
    values.push(input.postalCode || null);
  }
  if (input.street !== undefined) {
    updates.push('street = ?');
    values.push(input.street);
  }
  if (input.label !== undefined) {
    updates.push('label = ?');
    values.push(input.label);
  }
  if (input.isDefault !== undefined) {
    // If setting as default, unset other defaults
    if (input.isDefault) {
      await pool.query('UPDATE user_addresses SET is_default = FALSE WHERE user_id = ? AND id != ?', [userId, addressId]);
    }
    updates.push('is_default = ?');
    values.push(input.isDefault);
  }

  if (updates.length === 0) {
    const [rows] = await pool.query<AddressRow[]>('SELECT * FROM user_addresses WHERE id = ? AND user_id = ?', [addressId, userId]);
    if (rows.length === 0) {
      throw new Error('Address not found');
    }
    return mapAddress(rows[0]);
  }

  updates.push('updated_at = NOW()');
  values.push(addressId, userId);

  await pool.query(
    `UPDATE user_addresses SET ${updates.join(', ')} WHERE id = ? AND user_id = ?`,
    values,
  );

  const [rows] = await pool.query<AddressRow[]>('SELECT * FROM user_addresses WHERE id = ? AND user_id = ?', [addressId, userId]);
  if (rows.length === 0) {
    throw new Error('Address not found');
  }
  return mapAddress(rows[0]);
};

export const deleteAddress = async (addressId: string, userId: string): Promise<void> => {
  const pool = getPool();
  const [result] = await pool.query<{ affectedRows: number }>('DELETE FROM user_addresses WHERE id = ? AND user_id = ?', [addressId, userId]);
  if (result.affectedRows === 0) {
    throw new Error('Address not found');
  }
};






































