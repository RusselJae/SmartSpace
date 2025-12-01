import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  listAddressesByUser,
  createAddress,
  updateAddress,
  deleteAddress,
  CreateAddressInput,
  UpdateAddressInput,
} from '../services/address_service';

export const addressRouter = Router();

addressRouter.get(
  '/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'User ID is required' });
    }
    const addresses = await listAddressesByUser(userId);
    res.json({ success: true, data: addresses });
  }),
);

addressRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const input: CreateAddressInput = {
      userId: req.body.userId,
      fullName: req.body.fullName,
      phoneNumber: req.body.phoneNumber,
      region: req.body.region,
      postalCode: req.body.postalCode,
      street: req.body.street,
      label: req.body.label,
      isDefault: req.body.isDefault,
    };
    if (!input.userId || !input.fullName || !input.phoneNumber || !input.region || !input.street) {
      return res.status(400).json({ success: false, message: 'userId, fullName, phoneNumber, region, and street are required' });
    }
    const address = await createAddress(input);
    res.status(201).json({ success: true, data: address });
  }),
);

addressRouter.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const userId = req.body.userId;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required in request body' });
    }
    const input: UpdateAddressInput = {
      fullName: req.body.fullName,
      phoneNumber: req.body.phoneNumber,
      region: req.body.region,
      postalCode: req.body.postalCode,
      street: req.body.street,
      label: req.body.label,
      isDefault: req.body.isDefault,
    };
    const address = await updateAddress(id, userId, input);
    res.json({ success: true, data: address });
  }),
);

addressRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const userId = req.body.userId;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required in request body' });
    }
    await deleteAddress(id, userId);
    res.status(204).send();
  }),
);











