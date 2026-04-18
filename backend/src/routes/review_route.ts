import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/async_handler';
import {
  createReview,
  deleteReview,
  getReviewsByProductId,
  listReviews,
  listReviewsForUser,
  updateReviewStatus,
} from '../services/review_service';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS } from '../auth/admin_role';

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
  (req, res, next) => {
    const productId = req.query.productId as string | undefined;
    if (typeof productId === 'string' && productId.trim().length > 0) {
      return next();
    }
    const userId = req.query.userId as string | undefined;
    if (typeof userId === 'string' && userId.trim().length > 0) {
      return next();
    }
    return requireAdminAuth(req, res, () =>
      requireAdminPermission(ADMIN_PERMISSIONS.reviewsModerate)(req, res, next),
    );
  },
  asyncHandler(async (req, res) => {
    const productId = req.query.productId as string | undefined;
    const includePending =
      typeof req.query.includePending === 'string'
        ? req.query.includePending.toLowerCase() === 'true' || req.query.includePending === '1'
        : false;
    console.log(`[ReviewRoute] GET /reviews - productId: ${productId || 'none'}`);

    if (typeof productId === 'string' && productId.trim().length > 0) {
      console.log(`[ReviewRoute] includePending: ${includePending}`);
      const reviews = await getReviewsByProductId(productId.trim(), includePending);
      console.log(`[ReviewRoute] Returning ${reviews.length} reviews for productId: ${productId}`);
      res.json({ success: true, data: reviews });
      return;
    }
    const userId = req.query.userId as string | undefined;
    if (typeof userId === 'string' && userId.trim().length > 0) {
      const reviews = await listReviewsForUser(userId.trim());
      res.json({ success: true, data: reviews });
      return;
    }
    const reviews = await listReviews();
    console.log(`[ReviewRoute] Returning ${reviews.length} total reviews`);
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
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.reviewsModerate),
  asyncHandler(async (req, res) => {
    const payload = statusSchema.parse(req.body);
    await updateReviewStatus(req.params.id, payload.status);
    res.status(204).send();
  }),
);

reviewRouter.delete(
  '/:id',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.reviewsModerate),
  asyncHandler(async (req, res) => {
    await deleteReview(req.params.id);
    res.status(204).send();
  }),
);




