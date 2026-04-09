import { getPool } from '../config/database';
import { isSupabaseStorageEnabled } from './supabase_storage_service';
import { isCloudinaryUploadsEnabled } from './cloudinary_service';

/** Which backend handles new file uploads (derived from env at runtime). */
export type UploadsBackend = 'supabase' | 'cloudinary' | 'local';

export const getUploadsBackend = (): UploadsBackend => {
  if (isSupabaseStorageEnabled()) return 'supabase';
  if (isCloudinaryUploadsEnabled()) return 'cloudinary';
  return 'local';
};

export interface HealthStatus {
  readonly status: 'ok' | 'error';
  readonly database: 'connected' | 'disconnected';
  /** Where new uploads go — if `local`, Supabase env is missing or wrong on this host. */
  readonly uploads: UploadsBackend;
  readonly timestamp: string;
}

export const getHealthStatus = async (): Promise<HealthStatus> => {
  const uploads = getUploadsBackend();
  try {
    const pool = getPool();
    await pool.query('SELECT 1');
    return {
      status: 'ok',
      database: 'connected',
      uploads,
      timestamp: new Date().toISOString(),
    };
  } catch (error) {
    return {
      status: 'error',
      database: 'disconnected',
      uploads,
      timestamp: new Date().toISOString(),
    };
  }
};





