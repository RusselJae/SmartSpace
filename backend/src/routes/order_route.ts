import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/async_handler';
import { listOrders, createOrder, updateOrderStatus, CreateOrderInput } from '../services/order_service';

const statusSchema = z.object({
  status: z.string().min(1),
});

export const orderRouter = Router();

orderRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const orders = await listOrders();
    res.json({ success: true, data: orders });
  }),
);

orderRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const input: CreateOrderInput = {
      userId: req.body.userId,
      userName: req.body.userName,
      productIds: req.body.productIds ?? [],
      totalAmount: Number(req.body.totalAmount),
      shippingAddress: req.body.shippingAddress ?? {},
      status: req.body.status,
    };
    if (!input.userId || !input.userName || !input.productIds || input.productIds.length === 0) {
      return res.status(400).json({ success: false, message: 'userId, userName, and productIds are required' });
    }
    const order = await createOrder(input);
    res.status(201).json({ success: true, data: order });
  }),
);

orderRouter.patch(
  '/:id/status',
  asyncHandler(async (req, res) => {
    const payload = statusSchema.parse(req.body);
    await updateOrderStatus(req.params.id, payload.status);
    res.status(204).send();
  }),
);




