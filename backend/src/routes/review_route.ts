import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/async_handler';
import { createReview, deleteReview, listReviews, updateReviewStatus } from '../services/review_service';

const createReviewSchema = z.object({
  productId: z.string().min(1),
  productName: z.string().min(1),
  userId: z.string().min(1),
  userName: z.string().min(1),
  rating: z.coerce.number().min(1).max(5),
  content: z.string().min(1),
});

const statusSchema = z.object({
  status: z.string().min(1),
});

export const reviewRouter = Router();

reviewRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const reviews = await listReviews();
    res.json({ success: true, data: reviews });
  }),
);

reviewRouter.post(
  '/',
  asyncHandler(async (req, res) => {
    const payload = createReviewSchema.parse(req.body);
    const review = await createReview(payload);
    res.status(201).json({ success: true, data: review });
  }),
);

reviewRouter.patch(
  '/:id/status',
  asyncHandler(async (req, res) => {
    const payload = statusSchema.parse(req.body);
    await updateReviewStatus(req.params.id, payload.status);
    res.status(204).send();
  }),
);

reviewRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await deleteReview(req.params.id);
    res.status(204).send();
  }),
);




