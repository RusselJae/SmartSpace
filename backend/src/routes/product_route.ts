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

const productSchema = z.object({
  name: z.string().min(1),
  description: z.string().default(''),
  price: z.coerce.number().nonnegative(),
  category: z.string().min(1),
  style: z.string().default(''),
  material: z.string().default(''),
  color: z.string().default(''),
  modelPath: z.string().default('assets/chair.glb'),
  realWidthM: z.coerce.number().nonnegative().optional(),
  realHeightM: z.coerce.number().nonnegative().optional(),
  realDepthM: z.coerce.number().nonnegative().optional(),
  modelBaseScale: z.coerce.number().positive().max(100).default(1),
  imageUrls: z.array(z.string()).default([]),
  inventoryQty: z.coerce.number().nonnegative().optional(),
  isPopular: z.boolean().default(false),
  isNewArrival: z.boolean().default(false),
  inStock: z.boolean().default(true),
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
    const input = parseProductInput(req.body);
    const product = await createProduct(input);
    res.status(201).json({ success: true, data: product });
  }),
);

productRouter.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const input = parseProductInput(req.body);
    const product = await updateProduct(req.params.id, input);
    res.json({ success: true, data: product });
  }),
);

productRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await deleteProduct(req.params.id);
    res.status(204).send();
  }),
);




