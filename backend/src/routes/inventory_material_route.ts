import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/async_handler';
import {
  createInventoryMaterial,
  deleteInventoryMaterial,
  listInventoryMaterials,
  updateInventoryMaterial,
} from '../services/inventory_material_service';
import { logAdminActivity } from '../services/admin_activity_log_service';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS } from '../auth/admin_role';

export const inventoryMaterialRouter = Router();

const materialSchema = z.object({
  name: z.string().min(1),
  sku: z.string().optional().nullable(),
  unit: z.string().default('pcs'),
  quantityOnHand: z.coerce.number().nonnegative().default(0),
  reorderLevel: z.coerce.number().nonnegative().default(0),
  supplier: z.string().optional().nullable(),
  notes: z.string().optional().nullable(),
});

inventoryMaterialRouter.get(
  '/',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.inventoryWrite),
  asyncHandler(async (_req, res) => {
    const items = await listInventoryMaterials();
    res.json({ success: true, data: items });
  }),
);

inventoryMaterialRouter.post(
  '/',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.inventoryWrite),
  asyncHandler(async (req, res) => {
    const input = materialSchema.parse(req.body);
    const created = await createInventoryMaterial(input);
    await logAdminActivity({
      adminId: req.adminAuth!.id,
      action: 'inventory_material_created',
      entityType: 'inventory_material',
      entityId: created.id,
      details: { name: created.name },
    });
    res.status(201).json({ success: true, data: created });
  }),
);

inventoryMaterialRouter.put(
  '/:id',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.inventoryWrite),
  asyncHandler(async (req, res) => {
    const input = materialSchema.parse(req.body);
    const updated = await updateInventoryMaterial(req.params.id, input);
    await logAdminActivity({
      adminId: req.adminAuth!.id,
      action: 'inventory_material_updated',
      entityType: 'inventory_material',
      entityId: updated.id,
      details: { name: updated.name },
    });
    res.json({ success: true, data: updated });
  }),
);

inventoryMaterialRouter.delete(
  '/:id',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.inventoryWrite),
  asyncHandler(async (req, res) => {
    await deleteInventoryMaterial(req.params.id);
    await logAdminActivity({
      adminId: req.adminAuth!.id,
      action: 'inventory_material_deleted',
      entityType: 'inventory_material',
      entityId: req.params.id,
    });
    res.json({ success: true, data: null });
  }),
);
