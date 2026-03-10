import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/async_handler';
import { 
  listOrders, 
  createOrder, 
  updateOrderStatus, 
  confirmPayment,
  autoCancelUnpaidOrders,
  CreateOrderInput 
} from '../services/order_service';

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

/**
 * POST /api/orders/:id/confirm-payment
 * Admin endpoint to confirm payment proof and update order status
 * 
 * Body:
 * {
 *   adminId: string
 * }
 */
orderRouter.post(
  '/:id/confirm-payment',
  asyncHandler(async (req, res) => {
    const orderId = req.params.id;
    const adminId = req.body.adminId as string;
    
    if (!adminId) {
      return res.status(400).json({
        success: false,
        message: 'adminId is required',
      });
    }
    
    await confirmPayment(orderId, adminId);
    res.json({
      success: true,
      message: 'Payment confirmed successfully',
    });
  }),
);

/**
 * POST /api/orders/auto-cancel
 * Manually trigger auto-cancellation of unpaid orders (for testing/admin)
 * In production, this should be called by a cron job
 */
orderRouter.post(
  '/auto-cancel',
  asyncHandler(async (_req, res) => {
    const expiredCount = await autoCancelUnpaidOrders();
    res.json({
      success: true,
      message: `Auto-expired ${expiredCount} unpaid order(s)`,
      cancelledCount: expiredCount, // Keep for backward compatibility
    });
  }),
);




