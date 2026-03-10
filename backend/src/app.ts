import express, { Application } from 'express';
import cors from 'cors';
import { apiRouter } from './routes';
import { config } from './config/env';
import { errorHandler } from './middleware/error_handler';
import { ensureUploadsDirectories, uploadsRoot } from './utils/uploads';

export const createApp = (): Application => {
  const app = express();
  ensureUploadsDirectories();
  
  // Enhanced CORS configuration for Flutter Web and mobile devices
  // Allows connections from localhost, local network IPv4 addresses, and mobile apps
  app.use(cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (like mobile apps, Postman, etc.)
      if (!origin) {
        return callback(null, true);
      }
      
      // Allow all localhost origins (any port) - for web development
      const localhostRegex = /^https?:\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0)(:\d+)?$/;
      if (localhostRegex.test(origin)) {
        return callback(null, true);
      }
      
      // Allow local network IPv4 addresses (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
      // This enables physical devices on the same network to connect
      const localNetworkRegex = /^https?:\/\/(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3})(:\d+)?$/;
      if (localNetworkRegex.test(origin)) {
        return callback(null, true);
      }
      
      // In production, you might want to check against a whitelist
      // For development, allow all origins to prevent connection issues
      callback(null, true);
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept'],
    exposedHeaders: ['Content-Length', 'Content-Type'],
  }));
  
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true, limit: '50mb' }));

  // Serve uploaded files with proper CORS headers for WebXR
  app.use('/uploads', (req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type');
    res.header('Cross-Origin-Resource-Policy', 'cross-origin');
    next();
  }, express.static(uploadsRoot));
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





