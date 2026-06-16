import { RowDataPacket, ResultSetHeader } from 'mysql2';
import type { Connection, Pool } from 'mysql2/promise';
import { generateId } from '../utils/id_generator';
import { ensureProductVariantSchema } from './product_variant_service';

export type MaterialStockStatus = 'Out of stock' | 'Low stock' | 'In stock';

export type AggregatedMaterialRequirement = {
  readonly materialId: string;
  readonly materialName: string;
  readonly unit: string;
  readonly totalNeeded: number;
};

export type MaterialShortage = {
  readonly materialId: string;
  readonly materialName: string;
  readonly unit: string;
  readonly needed: number;
  readonly onHand: number;
  readonly shortBy: number;
};

type OrderItemRow = RowDataPacket & {
  readonly variant_id: string | null;
  readonly quantity: number;
  readonly product_id: string;
};

type BomLineRow = RowDataPacket & {
  readonly inventory_material_id: string;
  readonly quantity_required: number;
  readonly material_name: string;
  readonly material_unit: string;
};

type OnHandRow = RowDataPacket & {
  readonly quantity_on_hand: number;
  readonly reorder_level: number;
  readonly name: string;
  readonly unit: string;
};

type DeductionRow = RowDataPacket & {
  readonly inventory_material_id: string;
  readonly quantity_deducted: number;
};

type OrderMaterialsRow = RowDataPacket & {
  readonly materials_deducted_at: Date | string | null;
};

/**
 * Derives stock status from on-hand quantity and reorder threshold.
 * Uses reorder_level when set; falls back to 0 (only "Out of stock" vs "In stock").
 */
export const getMaterialStockStatus = (
  quantityOnHand: number,
  reorderLevel: number,
): MaterialStockStatus => {
  if (quantityOnHand <= 0) return 'Out of stock';
  if (quantityOnHand <= reorderLevel) return 'Low stock';
  return 'In stock';
};

const formatQty = (value: number): string => {
  const rounded = Math.round(value * 10000) / 10000;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(4).replace(/\.?0+$/, '');
};

export const formatMaterialShortageError = (shortages: readonly MaterialShortage[]): string => {
  const parts = shortages.map(
    (s) =>
      `${s.materialName} (need ${formatQty(s.needed)} ${s.unit}, have ${formatQty(s.onHand)} ${s.unit}, short ${formatQty(s.shortBy)} ${s.unit})`,
  );
  return `Insufficient raw materials: ${parts.join('; ')}`;
};

/**
 * Loads order line items and aggregates BOM requirements per inventory material.
 * Skips lines without a variant_id or without BOM entries.
 */
export const aggregateMaterialRequirementsForOrder = async (
  executor: Pool | Connection,
  orderId: string,
): Promise<Map<string, AggregatedMaterialRequirement>> => {
  await ensureProductVariantSchema();

  const [items] = await executor.query<OrderItemRow[]>(
    `SELECT variant_id, quantity, product_id FROM order_items WHERE order_id = ?`,
    [orderId],
  );

  const aggregated = new Map<string, AggregatedMaterialRequirement>();

  for (const item of items ?? []) {
    const variantId = item.variant_id;
    if (!variantId) continue;

    const orderQty = Number(item.quantity);
    if (!Number.isFinite(orderQty) || orderQty <= 0) continue;

    const [bomLines] = await executor.query<BomLineRow[]>(
      `SELECT bl.inventory_material_id, bl.quantity_required,
              m.name AS material_name, m.unit AS material_unit
       FROM product_variant_bom_lines bl
       INNER JOIN inventory_materials m ON m.id = bl.inventory_material_id
       WHERE bl.variant_id = ?`,
      [variantId],
    );

    for (const line of bomLines ?? []) {
      const materialId = line.inventory_material_id;
      const perUnit = Number(line.quantity_required);
      if (!Number.isFinite(perUnit) || perUnit <= 0) continue;

      const needed = perUnit * orderQty;
      const existing = aggregated.get(materialId);
      if (existing) {
        aggregated.set(materialId, {
          ...existing,
          totalNeeded: existing.totalNeeded + needed,
        });
      } else {
        aggregated.set(materialId, {
          materialId,
          materialName: line.material_name,
          unit: line.material_unit ?? 'pcs',
          totalNeeded: needed,
        });
      }
    }
  }

  return aggregated;
};

export const validateMaterialStockForOrder = async (
  executor: Pool | Connection,
  orderId: string,
): Promise<void> => {
  const requirements = await aggregateMaterialRequirementsForOrder(executor, orderId);
  if (requirements.size === 0) return;

  const shortages: MaterialShortage[] = [];

  for (const req of requirements.values()) {
    const [rows] = await executor.query<OnHandRow[]>(
      `SELECT quantity_on_hand, reorder_level, name, unit FROM inventory_materials WHERE id = ? LIMIT 1`,
      [req.materialId],
    );
    const row = rows?.[0];
    const onHand = row ? Number(row.quantity_on_hand) : 0;
    const name = row?.name ?? req.materialName;
    const unit = row?.unit ?? req.unit;

    if (onHand < req.totalNeeded) {
      shortages.push({
        materialId: req.materialId,
        materialName: name,
        unit,
        needed: req.totalNeeded,
        onHand,
        shortBy: req.totalNeeded - onHand,
      });
    }
  }

  if (shortages.length > 0) {
    throw new Error(formatMaterialShortageError(shortages));
  }
};

/**
 * Deducts aggregated BOM materials for an order inside an open transaction.
 * Idempotent: skips if materials were already deducted for this order.
 */
export const deductMaterialsForOrder = async (conn: Connection, orderId: string): Promise<void> => {
  await ensureProductVariantSchema();

  const [orderRows] = await conn.query<OrderMaterialsRow[]>(
    `SELECT materials_deducted_at FROM orders WHERE id = ? FOR UPDATE`,
    [orderId],
  );
  if (orderRows?.[0]?.materials_deducted_at != null) {
    return;
  }

  const requirements = await aggregateMaterialRequirementsForOrder(conn, orderId);
  if (requirements.size === 0) return;

  await validateMaterialStockForOrder(conn, orderId);

  for (const req of requirements.values()) {
    const [updateResult] = await conn.query<ResultSetHeader>(
      `UPDATE inventory_materials
       SET quantity_on_hand = quantity_on_hand - ?
       WHERE id = ? AND quantity_on_hand >= ?`,
      [req.totalNeeded, req.materialId, req.totalNeeded],
    );
    if ((updateResult.affectedRows ?? 0) !== 1) {
      throw new Error(
        `Failed to deduct ${req.materialName}: insufficient stock during transaction`,
      );
    }

    await conn.query(
      `INSERT INTO order_material_deductions (id, order_id, inventory_material_id, quantity_deducted)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE quantity_deducted = quantity_deducted + VALUES(quantity_deducted)`,
      [generateId('omd'), orderId, req.materialId, req.totalNeeded],
    );
  }

  await conn.query(`UPDATE orders SET materials_deducted_at = NOW() WHERE id = ?`, [orderId]);
};

/**
 * Restores materials previously deducted for an order.
 * Idempotent: no-op when nothing was deducted.
 */
export const restoreMaterialsForOrder = async (
  executor: Pool | Connection,
  orderId: string,
): Promise<void> => {
  await ensureProductVariantSchema();

  const [orderRows] = await executor.query<OrderMaterialsRow[]>(
    `SELECT materials_deducted_at FROM orders WHERE id = ? LIMIT 1`,
    [orderId],
  );
  if (orderRows?.[0]?.materials_deducted_at == null) {
    return;
  }

  const [deductions] = await executor.query<DeductionRow[]>(
    `SELECT inventory_material_id, quantity_deducted FROM order_material_deductions WHERE order_id = ?`,
    [orderId],
  );

  for (const row of deductions ?? []) {
    const qty = Number(row.quantity_deducted);
    if (!Number.isFinite(qty) || qty <= 0) continue;

    await executor.query(
      `UPDATE inventory_materials SET quantity_on_hand = quantity_on_hand + ? WHERE id = ?`,
      [qty, row.inventory_material_id],
    );
  }

  await executor.query(`DELETE FROM order_material_deductions WHERE order_id = ?`, [orderId]);
  await executor.query(`UPDATE orders SET materials_deducted_at = NULL WHERE id = ?`, [orderId]);
};

export const shouldRestoreMaterials = (previousStatus: string, nextStatus: string): boolean => {
  if (nextStatus !== 'cancelled' && nextStatus !== 'expired' && nextStatus !== 'refunded') {
    return false;
  }
  if (previousStatus === 'cancelled' || previousStatus === 'expired' || previousStatus === 'refunded') {
    return false;
  }
  return previousStatus === 'confirmed' || previousStatus === 'shipped' || previousStatus === 'delivered';
};
