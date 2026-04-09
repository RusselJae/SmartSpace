import { createClient, SupabaseClient } from '@supabase/supabase-js';

/**
 * Supabase Storage for uploads (models, images, etc.). Keeps MySQL as the app DB; only Storage is used.
 *
 * Required env:
 * - SUPABASE_URL — Project Settings → API → Project URL
 * - SUPABASE_SERVICE_ROLE_KEY — service_role secret (server only; never expose to Flutter/web)
 *
 * Optional:
 * - SUPABASE_STORAGE_BUCKET — bucket name (create in Dashboard → Storage), default smartspace-uploads
 * - SUPABASE_STORAGE_KEY_PREFIX — default smartspace (paths: {prefix}/models/...)
 *
 * Bucket must allow public read if you use getPublicUrl (recommended for AR model URLs).
 * In Dashboard: Storage → bucket → Public bucket, or add a policy for read.
 */

let client: SupabaseClient | null = null;

export const isSupabaseStorageEnabled = (): boolean => {
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  return Boolean(url && key);
};

export const supabaseStorageBucket = (): string => {
  const b = process.env.SUPABASE_STORAGE_BUCKET?.trim();
  return b != null && b.length > 0 ? b : 'smartspace-uploads';
};

export const keyPrefix = (): string => {
  const p = process.env.SUPABASE_STORAGE_KEY_PREFIX?.trim();
  return p != null && p.length > 0 ? p.replace(/^\/+|\/+$/g, '') : 'smartspace';
};

const getClient = (): SupabaseClient => {
  if (client != null) return client;
  client = createClient(process.env.SUPABASE_URL!.trim(), process.env.SUPABASE_SERVICE_ROLE_KEY!.trim(), {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
  return client;
};

const assertKeyAllowed = (objectKey: string): void => {
  const prefix = keyPrefix();
  const normalized = objectKey.trim();
  if (normalized.length === 0) {
    throw new Error('Empty key');
  }
  if (!normalized.startsWith(`${prefix}/`)) {
    throw new Error('Invalid object key');
  }
};

/**
 * Upload a buffer. Object key = {prefix}/{subKey}.
 */
export const uploadToSupabaseStorage = async (params: {
  subKey: string;
  buffer: Buffer;
  contentType?: string;
}): Promise<{ publicUrl: string; objectKey: string }> => {
  const prefix = keyPrefix();
  const sub = params.subKey.replace(/^\/+/, '');
  const objectKey = `${prefix}/${sub}`;
  const bucket = supabaseStorageBucket();
  const sb = getClient();

  const { error } = await sb.storage.from(bucket).upload(objectKey, params.buffer, {
    contentType: params.contentType ?? 'application/octet-stream',
    upsert: true,
  });

  if (error != null) {
    throw new Error(error.message);
  }

  const { data } = sb.storage.from(bucket).getPublicUrl(objectKey);

  return {
    objectKey,
    publicUrl: data.publicUrl,
  };
};

export const deleteFromSupabaseStorage = async (objectKey: string): Promise<boolean> => {
  if (!isSupabaseStorageEnabled()) return false;
  assertKeyAllowed(objectKey);
  const bucket = supabaseStorageBucket();
  const sb = getClient();
  const { error } = await sb.storage.from(bucket).remove([objectKey]);
  if (error != null) {
    throw new Error(error.message);
  }
  return true;
};

export const tryDeleteSupabaseStorage = async (objectKey: string): Promise<boolean> => {
  try {
    return await deleteFromSupabaseStorage(objectKey);
  } catch {
    return false;
  }
};
