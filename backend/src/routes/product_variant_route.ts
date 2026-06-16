import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/async_handler';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS } from '../auth/admin_role';
import {
  createProductVariant,
  deleteProductVariant,
  getVariantById,
  listVariantsForProduct,
  updateProductVariant,
} from '../services/product_variant_service';

const bomLineSchema = z.object({
  inventoryMaterialId: z.string().min(1),
  quantityRequired: z.coerce.number().positive(),
});

const variantSchema = z.object({
  name: z.string().min(1),
  dimensionsLabel: z.string().nullable().optional(),
  priceAdjustment: z.coerce.number().optional(),
  isDefault: z.boolean().optional(),
  bomLines: z.array(bomLineSchema).optional(),
});

export const productVariantRouter = Router({ mergeParams: true });

productVariantRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const productId = req.params.productId as string;
    const variants = await listVariantsForProduct(productId);
    res.json({ success: true, data: variants });
  }),
);

productVariantRouter.get(
  '/:variantId',
  asyncHandler(async (req, res) => {
    const variant = await getVariantById(req.params.variantId as string);
    if (!variant) {
      res.status(404).json({ success: false, message: 'Variant not found' });
      return;
    }
    res.json({ success: true, data: variant });
  }),
);

productVariantRouter.post(
  '/',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.productsWrite),
  asyncHandler(async (req, res) => {
    const productId = req.params.productId as string;
    const input = variantSchema.parse(req.body);
    const variant = await createProductVariant(productId, input);
    res.status(201).json({ success: true, data: variant });
  }),
);

productVariantRouter.put(
  '/:variantId',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.productsWrite),
  asyncHandler(async (req, res) => {
    const input = variantSchema.parse(req.body);
    const variant = await updateProductVariant(req.params.variantId as string, input);
    res.json({ success: true, data: variant });
  }),
);

productVariantRouter.delete(
  '/:variantId',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.productsWrite),
  asyncHandler(async (req, res) => {
    await deleteProductVariant(req.params.variantId as string);
    res.json({ success: true });
  }),
);
