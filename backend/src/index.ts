import { createServer, Server } from 'http';
import { createApp } from './app';
import { config } from './config/env';
import { getPool } from './config/database';

const startServer = (): Server => {
  const app = createApp();
  const server = createServer(app);
  server.listen(config.port, () => {
    console.log(`🚀 ${config.appName} listening on port ${config.port}`);
  });
  return server;
};

const initialize = async (): Promise<void> => {
  try {
    const pool = getPool();
    await pool.query('SELECT 1');
    startServer();
  } catch (error) {
    console.error('Failed to initialize database connection', error);
    process.exit(1);
  }
};

void initialize();





