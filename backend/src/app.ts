import express, { Application } from 'express';
import cors from 'cors';
import { apiRouter } from './routes';
import { config } from './config/env';
import { errorHandler } from './middleware/error_handler';
import { ensureUploadsDirectories, uploadsRoot } from './utils/uploads';

export const createApp = (): Application => {
  const app = express();
  ensureUploadsDirectories();
  
  // Enhanced CORS configuration for Flutter Web
  // Allow all localhost origins (Flutter Web uses random ports)
  app.use(cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (like mobile apps, Postman, etc.)
      if (!origin) {
        return callback(null, true);
      }
      
      // Allow all localhost origins (any port)
      const localhostRegex = /^https?:\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0)(:\d+)?$/;
      if (localhostRegex.test(origin)) {
        return callback(null, true);
      }
      
      // In production, you might want to check against a whitelist
      // For development, allow all localhost
      callback(null, true);
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept'],
    exposedHeaders: ['Content-Length', 'Content-Type'],
  }));
  
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true }));

  app.use('/uploads', express.static(uploadsRoot));
  app.use('/api', apiRouter);

  app.get('/', (_req, res) => {
    res.json({
      success: true,
      message: `${config.appName} running`,
      environment: config.environment,
    });
  });

  app.use(errorHandler);
  return app;
};





