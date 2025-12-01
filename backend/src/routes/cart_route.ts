import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  addCartItem,
  clearCart,
  listCartItemsByUser,
  removeCartItem,
  setCartItemQuantity,
} from '../services/cart_service';

export const cartRouter = Router();

cartRouter.get(
  '/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'User ID is required' });
    }
    const items = await listCartItemsByUser(userId);
    res.json({ success: true, data: items });
  }),
);

cartRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const { userId, productId } = req.body;
    if (!userId || !productId) {
      return res.status(400).json({ success: false, message: 'userId and productId are required' });
    }
    const quantity = Number.isFinite(Number(req.body.quantity)) ? Number(req.body.quantity) : 1;
    const item = await addCartItem({
      userId,
      productId,
      quantity,
      notes: req.body.notes,
    });
    res.status(201).json({ success: true, data: item });
  }),
);

cartRouter.patch(
  '/',
  asyncHandler(async (req, res) => {
    const { userId, productId } = req.body;
    if (!userId || !productId || req.body.quantity == null) {
      return res
        .status(400)
        .json({ success: false, message: 'userId, productId and quantity are required' });
    }
    const quantity = Number(req.body.quantity);
    if (!Number.isFinite(quantity)) {
      return res.status(400).json({ success: false, message: 'quantity must be a number' });
    }
    const item = await setCartItemQuantity({
      userId,
      productId,
      quantity,
      notes: req.body.notes,
    });
    res.json({ success: true, data: item });
  }),
);

cartRouter.delete(
  '/:userId/:productId',
  asyncHandler(async (req, res) => {
    const { userId, productId } = req.params;
    if (!userId || !productId) {
      return res.status(400).json({ success: false, message: 'userId and productId are required' });
    }
    await removeCartItem(userId, productId);
    res.status(204).send();
  }),
);

cartRouter.delete(
  '/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'User ID is required' });
    }
    await clearCart(userId);
    res.status(204).send();
  }),
);













