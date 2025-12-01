import { getPool } from '../config/database';

export interface HealthStatus {
  readonly status: 'ok' | 'error';
  readonly database: 'connected' | 'disconnected';
  readonly timestamp: string;
}

export const getHealthStatus = async (): Promise<HealthStatus> => {
  try {
    const pool = getPool();
    await pool.query('SELECT 1');
    return {
      status: 'ok',
      database: 'connected',
      timestamp: new Date().toISOString(),
    };
  } catch (error) {
    return {
      status: 'error',
      database: 'disconnected',
      timestamp: new Date().toISOString(),
    };
  }
};





