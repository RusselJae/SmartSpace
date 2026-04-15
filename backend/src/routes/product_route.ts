import { Router } from 'express';
import { z } from 'zod';
import {
  createProduct,
  deleteProduct,
  listProducts,
  ProductInput,
  updateProduct,
} from '../services/product_service';
import { asyncHandler } from '../utils/async_handler';
import { logAdminActivity } from '../services/admin_activity_log_service';

const productComponentSchema = z.object({
  name: z.string().min(1),
  quantity: z.coerce.number().int().positive(),
  widthM: z.coerce.number().positive(),
  heightM: z.coerce.number().positive(),
  depthM: z.coerce.number().positive(),
  modelPath: z.string().optional(),
  notes: z.string().optional(),
});

const productSchema = z.object({
  name: z.string().min(1),
  description: z.string().default(''),
  price: z.coerce.number().nonnegative(),
  category: z.string().min(1),
  style: z.string().default(''),
  material: z.string().default(''),
  color: z.string().default(''),
  modelPath: z.string().default('assets/chair.glb'),
  components: z.array(productComponentSchema).default([]),
  realWidthM: z.coerce.number().nonnegative().optional(),
  realHeightM: z.coerce.number().nonnegative().optional(),
  realDepthM: z.coerce.number().nonnegative().optional(),
  modelBaseScale: z.coerce.number().positive().max(100).default(1),
  imageUrls: z.array(z.string()).default([]),
  inventoryQty: z.coerce.number().nonnegative().optional(),
  isPopular: z.boolean().default(false),
  isNewArrival: z.boolean().default(false),
  inStock: z.boolean().default(true),
  // Admin-only flag. Archived products remain in the database but are hidden from the main catalog.
  isArchived: z.boolean().default(false),
});

const parseProductInput = (payload: unknown): ProductInput => {
  return productSchema.parse(payload);
};

export const productRouter = Router();

productRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const products = await listProducts();
    res.json({ success: true, data: products });
  }),
);

productRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const adminId = req.body.adminId != null ? String(req.body.adminId).trim() : '';
    const input = parseProductInput(req.body);
    const product = await createProduct(input);
    if (adminId.length > 0) {
      await logAdminActivity({
        adminId,
        action: 'product_created',
        entityType: 'product',
        entityId: product.id,
        details: { name: product.name },
      });
    }
    res.status(201).json({ success: true, data: product });
  }),
);

productRouter.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const adminId = req.body.adminId != null ? String(req.body.adminId).trim() : '';
    const input = parseProductInput(req.body);
    const product = await updateProduct(req.params.id, input);
    if (adminId.length > 0) {
      await logAdminActivity({
        adminId,
        action: 'product_updated',
        entityType: 'product',
        entityId: product.id,
        details: { name: product.name },
      });
    }
    res.json({ success: true, data: product });
  }),
);

productRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const adminId = req.query.adminId != null ? String(req.query.adminId).trim() : '';
    await deleteProduct(req.params.id);
    if (adminId.length > 0) {
      await logAdminActivity({
        adminId,
        action: 'product_deleted',
        entityType: 'product',
        entityId: req.params.id,
      });
    }
    res.status(204).send();
  }),
);




