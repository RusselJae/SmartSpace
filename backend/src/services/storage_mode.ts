import { isSupabaseStorageEnabled } from './supabase_storage_service';
import { isCloudinaryUploadsEnabled } from './cloudinary_service';

/** Multer should use memory buffers when uploading to Supabase Storage or Cloudinary (not local disk). */
export const shouldUseMemoryBufferUpload = (): boolean =>
  isSupabaseStorageEnabled() || isCloudinaryUploadsEnabled();
