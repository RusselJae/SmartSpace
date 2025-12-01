import { Router } from 'express';
import { getHealthStatus } from '../services/health_service';

export const healthRouter = Router();

healthRouter.get('/', async (_req, res) => {
  const status = await getHealthStatus();
  res.json({ success: true, data: status });
});





