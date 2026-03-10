import { Router } from 'express';
import { healthRouter } from './health_route';
import { productRouter } from './product_route';
import { userRouter } from './user_route';
import { orderRouter } from './order_route';
import { reviewRouter } from './review_route';
import { cartRouter } from './cart_route';
import { addressRouter } from './address_route';
import { adminRouter } from './admin_route';
import { adminAuthRouter } from './admin_auth_route';
import { modelRouter } from './model_route';
import { imageRouter } from './image_route';
import { paymentProofRouter } from './payment_proof_route';

export const apiRouter = Router();

apiRouter.use('/health', healthRouter);
apiRouter.use('/products', productRouter);
apiRouter.use('/users', userRouter);
apiRouter.use('/orders', orderRouter);
apiRouter.use('/reviews', reviewRouter);
apiRouter.use('/cart', cartRouter);
apiRouter.use('/addresses', addressRouter);
apiRouter.use('/admins', adminRouter);
apiRouter.use('/admin-auth', adminAuthRouter);
apiRouter.use('/models', modelRouter);
apiRouter.use('/images', imageRouter);
apiRouter.use('/payment-proofs', paymentProofRouter);


