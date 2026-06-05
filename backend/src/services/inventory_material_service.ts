import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';

let _schemaEnsured = false;

const ensureSchema = async (): Promise<void> => {
  if (_schemaEnsured) return;
  const pool = getPool();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS inventory_materials (
      id              VARCHAR(50) PRIMARY KEY,
      name            VARCHAR(255) NOT NULL,
      sku             VARCHAR(80) NULL,
      unit            VARCHAR(32) NOT NULL DEFAULT 'pcs',
      quantity_on_hand DECIMAL(12,2) NOT NULL DEFAULT 0,
      reorder_level   DECIMAL(12,2) NOT NULL DEFAULT 0,
      supplier        VARCHAR(255) NULL,
      notes           TEXT NULL,
      created_at      TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at      TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_material_name (name),
      KEY idx_material_sku (sku)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
  _schemaEnsured = true;
};

type MaterialRow = RowDataPacket & {
  readonly id: string;
  readonly name: string;
  readonly sku: string | null;
  readonly unit: string;
  readonly quantity_on_hand: number;
  readonly reorder_level: number;
  readonly supplier: string | null;
  readonly notes: string | null;
  readonly created_at: Date;
  readonly updated_at: Date;
};

export type InventoryMaterial = {
  readonly id: string;
  readonly name: string;
  readonly sku: string | null;
  readonly unit: string;
  readonly quantityOnHand: number;
  readonly reorderLevel: number;
  readonly supplier: string | null;
  readonly notes: string | null;
  readonly createdAt: Date;
  readonly updatedAt: Date;
};

const rowToMaterial = (row: MaterialRow): InventoryMaterial => ({
  id: row.id,
  name: row.name,
  sku: row.sku,
  unit: row.unit ?? 'pcs',
  quantityOnHand: Number(row.quantity_on_hand ?? 0),
  reorderLevel: Number(row.reorder_level ?? 0),
  supplier: row.supplier,
  notes: row.notes,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export type InventoryMaterialInput = {
  name: string;
  sku?: string | null;
  unit?: string;
  quantityOnHand?: number;
  reorderLevel?: number;
  supplier?: string | null;
  notes?: string | null;
};

export const listInventoryMaterials = async (): Promise<InventoryMaterial[]> => {
  await ensureSchema();
  const pool = getPool();
  const [rows] = await pool.query<MaterialRow[]>(
    `SELECT id, name, sku, unit, quantity_on_hand, reorder_level, supplier, notes, created_at, updated_at
     FROM inventory_materials
     ORDER BY name ASC`,
  );
  return (rows ?? []).map(rowToMaterial);
};

export const createInventoryMaterial = async (
  input: InventoryMaterialInput,
): Promise<InventoryMaterial> => {
  await ensureSchema();
  const pool = getPool();
  const id = generateId('mat');
  await pool.query(
    `INSERT INTO inventory_materials
      (id, name, sku, unit, quantity_on_hand, reorder_level, supplier, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      input.name.trim(),
      input.sku?.trim() || null,
      (input.unit ?? 'pcs').trim() || 'pcs',
      input.quantityOnHand ?? 0,
      input.reorderLevel ?? 0,
      input.supplier?.trim() || null,
      input.notes?.trim() || null,
    ],
  );
  const [rows] = await pool.query<MaterialRow[]>(
    `SELECT id, name, sku, unit, quantity_on_hand, reorder_level, supplier, notes, created_at, updated_at
     FROM inventory_materials WHERE id = ?`,
    [id],
  );
  const row = rows?.[0];
  if (!row) throw new Error('Failed to fetch created material');
  return rowToMaterial(row);
};

export const updateInventoryMaterial = async (
  id: string,
  input: InventoryMaterialInput,
): Promise<InventoryMaterial> => {
  await ensureSchema();
  const pool = getPool();
  const [result] = await pool.query<ResultSetHeader>(
    `UPDATE inventory_materials SET
      name = ?, sku = ?, unit = ?, quantity_on_hand = ?, reorder_level = ?, supplier = ?, notes = ?
     WHERE id = ?`,
    [
      input.name.trim(),
      input.sku?.trim() || null,
      (input.unit ?? 'pcs').trim() || 'pcs',
      input.quantityOnHand ?? 0,
      input.reorderLevel ?? 0,
      input.supplier?.trim() || null,
      input.notes?.trim() || null,
      id,
    ],
  );
  if ((result.affectedRows ?? 0) === 0) {
    throw new Error('Material not found');
  }
  const [rows] = await pool.query<MaterialRow[]>(
    `SELECT id, name, sku, unit, quantity_on_hand, reorder_level, supplier, notes, created_at, updated_at
     FROM inventory_materials WHERE id = ?`,
    [id],
  );
  const row = rows?.[0];
  if (!row) throw new Error('Material not found');
  return rowToMaterial(row);
};

export const deleteInventoryMaterial = async (id: string): Promise<void> => {
  await ensureSchema();
  const pool = getPool();
  const [result] = await pool.query<ResultSetHeader>(
    `DELETE FROM inventory_materials WHERE id = ?`,
    [id],
  );
  if ((result.affectedRows ?? 0) === 0) {
    throw new Error('Material not found');
  }
};
