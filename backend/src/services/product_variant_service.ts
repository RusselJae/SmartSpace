import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';
import {
  ProductVariant,
  ProductVariantBomLine,
  ProductVariantInput,
} from '../models/product_variant';
import { ensureSchema as ensureInventoryMaterialsSchema } from './inventory_material_service';

let _schemaEnsured = false;

export const ensureProductVariantSchema = async (): Promise<void> => {
  if (_schemaEnsured) return;
  await ensureInventoryMaterialsSchema();
  const pool = getPool();

  await pool.query(`
    CREATE TABLE IF NOT EXISTS product_variants (
      id                VARCHAR(50) PRIMARY KEY,
      product_id        VARCHAR(50) NOT NULL,
      name              VARCHAR(255) NOT NULL,
      dimensions_label  VARCHAR(255) NULL,
      price_adjustment  DECIMAL(10,2) NOT NULL DEFAULT 0,
      is_default        TINYINT(1) NOT NULL DEFAULT 0,
      created_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_variant_product (product_id),
      CONSTRAINT fk_variant_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS product_variant_bom_lines (
      id                    VARCHAR(50) PRIMARY KEY,
      variant_id            VARCHAR(50) NOT NULL,
      inventory_material_id VARCHAR(50) NOT NULL,
      quantity_required     DECIMAL(12,4) NOT NULL,
      created_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uq_variant_material (variant_id, inventory_material_id),
      KEY idx_bom_variant (variant_id),
      KEY idx_bom_material (inventory_material_id),
      CONSTRAINT fk_bom_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE,
      CONSTRAINT fk_bom_material FOREIGN KEY (inventory_material_id) REFERENCES inventory_materials(id) ON DELETE RESTRICT
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  try {
    await pool.query(`
      ALTER TABLE order_items
      ADD COLUMN variant_id VARCHAR(50) NULL DEFAULT NULL AFTER product_id,
      ADD KEY idx_order_items_variant (variant_id)
    `);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (!msg.includes('Duplicate column') && !msg.toLowerCase().includes('duplicate column name')) {
      console.warn('ensureProductVariantSchema order_items.variant_id:', msg);
    }
  }

  try {
    await pool.query(`
      ALTER TABLE orders
      ADD COLUMN materials_deducted_at TIMESTAMP NULL DEFAULT NULL
      COMMENT 'When raw materials were deducted for this order'
    `);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (!msg.includes('Duplicate column') && !msg.toLowerCase().includes('duplicate column name')) {
      console.warn('ensureProductVariantSchema orders.materials_deducted_at:', msg);
    }
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS order_material_deductions (
      id                    VARCHAR(50) PRIMARY KEY,
      order_id              VARCHAR(50) NOT NULL,
      inventory_material_id VARCHAR(50) NOT NULL,
      quantity_deducted     DECIMAL(12,4) NOT NULL,
      created_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_order_material (order_id, inventory_material_id),
      KEY idx_omd_order (order_id),
      CONSTRAINT fk_omd_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
      CONSTRAINT fk_omd_material FOREIGN KEY (inventory_material_id) REFERENCES inventory_materials(id) ON DELETE RESTRICT
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  _schemaEnsured = true;
};

type VariantRow = RowDataPacket & {
  readonly id: string;
  readonly product_id: string;
  readonly name: string;
  readonly dimensions_label: string | null;
  readonly price_adjustment: number;
  readonly is_default: number | boolean;
  readonly created_at: Date;
  readonly updated_at: Date;
};

type BomRow = RowDataPacket & {
  readonly id: string;
  readonly variant_id: string;
  readonly inventory_material_id: string;
  readonly quantity_required: number;
  readonly material_name: string;
  readonly material_sku: string | null;
  readonly material_unit: string;
};

const mapBomLine = (row: BomRow): ProductVariantBomLine => ({
  id: row.id,
  variantId: row.variant_id,
  inventoryMaterialId: row.inventory_material_id,
  materialName: row.material_name,
  materialSku: row.material_sku,
  materialUnit: row.material_unit ?? 'pcs',
  quantityRequired: Number(row.quantity_required),
});

const fetchBomLinesForVariants = async (variantIds: readonly string[]): Promise<Map<string, ProductVariantBomLine[]>> => {
  const result = new Map<string, ProductVariantBomLine[]>();
  if (variantIds.length === 0) return result;

  await ensureProductVariantSchema();
  const pool = getPool();
  const placeholders = variantIds.map(() => '?').join(', ');
  const [rows] = await pool.query<BomRow[]>(
    `SELECT bl.id, bl.variant_id, bl.inventory_material_id, bl.quantity_required,
            m.name AS material_name, m.sku AS material_sku, m.unit AS material_unit
     FROM product_variant_bom_lines bl
     INNER JOIN inventory_materials m ON m.id = bl.inventory_material_id
     WHERE bl.variant_id IN (${placeholders})`,
    [...variantIds],
  );

  for (const row of rows ?? []) {
    const list = result.get(row.variant_id) ?? [];
    list.push(mapBomLine(row));
    result.set(row.variant_id, list);
  }
  return result;
};

const mapVariant = (row: VariantRow, bomLines: ProductVariantBomLine[]): ProductVariant => ({
  id: row.id,
  productId: row.product_id,
  name: row.name,
  dimensionsLabel: row.dimensions_label,
  priceAdjustment: Number(row.price_adjustment ?? 0),
  isDefault: Boolean(row.is_default),
  bomLines,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export const listVariantsForProduct = async (productId: string): Promise<ProductVariant[]> => {
  await ensureProductVariantSchema();
  const pool = getPool();
  const [rows] = await pool.query<VariantRow[]>(
    `SELECT id, product_id, name, dimensions_label, price_adjustment, is_default, created_at, updated_at
     FROM product_variants
     WHERE product_id = ?
     ORDER BY is_default DESC, name ASC`,
    [productId],
  );
  const variantIds = (rows ?? []).map((r) => r.id);
  const bomByVariant = await fetchBomLinesForVariants(variantIds);
  return (rows ?? []).map((row) => mapVariant(row, bomByVariant.get(row.id) ?? []));
};

export const getVariantById = async (variantId: string): Promise<ProductVariant | null> => {
  await ensureProductVariantSchema();
  const pool = getPool();
  const [rows] = await pool.query<VariantRow[]>(
    `SELECT id, product_id, name, dimensions_label, price_adjustment, is_default, created_at, updated_at
     FROM product_variants WHERE id = ? LIMIT 1`,
    [variantId],
  );
  const row = rows?.[0];
  if (!row) return null;
  const bomByVariant = await fetchBomLinesForVariants([row.id]);
  return mapVariant(row, bomByVariant.get(row.id) ?? []);
};

const replaceBomLines = async (
  variantId: string,
  bomLines: ProductVariantInput['bomLines'],
): Promise<void> => {
  const pool = getPool();
  await pool.query(`DELETE FROM product_variant_bom_lines WHERE variant_id = ?`, [variantId]);
  if (!bomLines || bomLines.length === 0) return;

  for (const line of bomLines) {
    const qty = Number(line.quantityRequired);
    if (!Number.isFinite(qty) || qty <= 0) {
      throw new Error('BOM quantity must be a positive number');
    }
    await pool.query(
      `INSERT INTO product_variant_bom_lines (id, variant_id, inventory_material_id, quantity_required)
       VALUES (?, ?, ?, ?)`,
      [generateId('bom'), variantId, line.inventoryMaterialId, qty],
    );
  }
};

export const createProductVariant = async (
  productId: string,
  input: ProductVariantInput,
): Promise<ProductVariant> => {
  await ensureProductVariantSchema();
  const pool = getPool();
  const id = generateId('var');

  if (input.isDefault) {
    await pool.query(`UPDATE product_variants SET is_default = 0 WHERE product_id = ?`, [productId]);
  }

  await pool.query(
    `INSERT INTO product_variants (id, product_id, name, dimensions_label, price_adjustment, is_default)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      id,
      productId,
      input.name.trim(),
      input.dimensionsLabel?.trim() || null,
      input.priceAdjustment ?? 0,
      input.isDefault ? 1 : 0,
    ],
  );

  await replaceBomLines(id, input.bomLines);
  const created = await getVariantById(id);
  if (!created) throw new Error('Failed to fetch created variant');
  return created;
};

export const updateProductVariant = async (
  variantId: string,
  input: ProductVariantInput,
): Promise<ProductVariant> => {
  await ensureProductVariantSchema();
  const pool = getPool();
  const existing = await getVariantById(variantId);
  if (!existing) throw new Error('Variant not found');

  if (input.isDefault) {
    await pool.query(`UPDATE product_variants SET is_default = 0 WHERE product_id = ?`, [existing.productId]);
  }

  const [result] = await pool.query<ResultSetHeader>(
    `UPDATE product_variants SET
      name = ?, dimensions_label = ?, price_adjustment = ?, is_default = ?
     WHERE id = ?`,
    [
      input.name.trim(),
      input.dimensionsLabel?.trim() || null,
      input.priceAdjustment ?? 0,
      input.isDefault ? 1 : 0,
      variantId,
    ],
  );
  if ((result.affectedRows ?? 0) === 0) {
    throw new Error('Variant not found');
  }

  if (input.bomLines !== undefined) {
    await replaceBomLines(variantId, input.bomLines);
  }

  const updated = await getVariantById(variantId);
  if (!updated) throw new Error('Variant not found');
  return updated;
};

export const deleteProductVariant = async (variantId: string): Promise<void> => {
  await ensureProductVariantSchema();
  const pool = getPool();
  const [result] = await pool.query<ResultSetHeader>(
    `DELETE FROM product_variants WHERE id = ?`,
    [variantId],
  );
  if ((result.affectedRows ?? 0) === 0) {
    throw new Error('Variant not found');
  }
};
