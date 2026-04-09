import { Readable } from 'stream';
import { v2 as cloudinary } from 'cloudinary';
import { isSupabaseStorageEnabled } from './supabase_storage_service';

/**
 * Cloudinary uploads for models (GLB/GLTF as raw), images, avatars, payment proofs, etc.
 * When CLOUDINARY_* env vars are all set, upload routes use Cloudinary instead of local disk
 * so files survive Railway/Render redeploys.
 * If Supabase Storage is configured, it takes precedence and Cloudinary is not used for new uploads.
 */

const baseFolder = (): string => {
  const raw = process.env.CLOUDINARY_FOLDER?.trim();
  return raw != null && raw.length > 0 ? raw.replace(/^\/+|\/+$/g, '') : 'smartspace';
};

/** True when Cloudinary should be used for new uploads (Supabase Storage is not active). */
export const isCloudinaryUploadsEnabled = (): boolean => {
  if (isSupabaseStorageEnabled()) return false;
  const n = process.env.CLOUDINARY_CLOUD_NAME?.trim();
  const k = process.env.CLOUDINARY_API_KEY?.trim();
  const s = process.env.CLOUDINARY_API_SECRET?.trim();
  return Boolean(n && k && s);
};

const ensureConfigured = (): void => {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
  });
};

/** Safe fragment for Cloudinary public_id / folder segments. */
export const sanitizeCloudinarySegment = (value: string, maxLen = 100): string => {
  const cleaned = value
    .toLowerCase()
    .replace(/[^a-z0-9-_]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
  const base = cleaned.length > 0 ? cleaned : 'default';
  return base.length > maxLen ? base.substring(0, maxLen) : base;
};

const uploadStream = (
  buffer: Buffer,
  options: {
    folder: string;
    publicId: string;
    resourceType: 'image' | 'raw';
    mimeType?: string;
  },
): Promise<{ secureUrl: string; publicId: string }> => {
  ensureConfigured();
  const folder = options.folder.replace(/^\/+|\/+$/g, '');

  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder,
        public_id: options.publicId,
        resource_type: options.resourceType,
        overwrite: true,
      },
      (err, result) => {
        if (err != null) {
          reject(err);
          return;
        }
        if (result?.secure_url == null || result.public_id == null) {
          reject(new Error('Cloudinary upload returned no URL'));
          return;
        }
        resolve({ secureUrl: result.secure_url, publicId: result.public_id });
      },
    );

    Readable.from(buffer).pipe(stream);
  });
};

/**
 * Product images, avatars, JPEG/PNG/WebP, etc.
 */
export const uploadImageBuffer = async (params: {
  /** Logical subpath under base folder, e.g. `images/my-product` */
  subFolder: string;
  /** Filename body + extension, e.g. `photo_12345.jpg` */
  fileName: string;
  buffer: Buffer;
}): Promise<{ secureUrl: string; publicId: string }> => {
  const folder = `${baseFolder()}/${params.subFolder.replace(/^\/+|\/+$/g, '')}`;
  const ext = params.fileName.includes('.') ? params.fileName.substring(params.fileName.lastIndexOf('.')) : '';
  const base = ext ? params.fileName.substring(0, params.fileName.lastIndexOf('.')) : params.fileName;
  const publicId = `${sanitizeCloudinarySegment(base, 80)}${ext}`;
  return uploadStream(params.buffer, {
    folder,
    publicId,
    resourceType: 'image',
  });
};

/**
 * GLB/GLTF and other non-image binaries (payment PDFs, chat attachments).
 */
export const uploadRawBuffer = async (params: {
  subFolder: string;
  fileName: string;
  buffer: Buffer;
  mimeType?: string;
}): Promise<{ secureUrl: string; publicId: string }> => {
  const folder = `${baseFolder()}/${params.subFolder.replace(/^\/+|\/+$/g, '')}`;
  const publicId = params.fileName.replace(/[^a-zA-Z0-9-_.]/g, '_').substring(0, 120);
  return uploadStream(params.buffer, {
    folder,
    publicId,
    resourceType: 'raw',
    mimeType: params.mimeType,
  });
};

/**
 * Delete by full public_id (e.g. `smartspace/models/foo/bar.glb`).
 * @returns true if Cloudinary reported the asset was removed (`result: ok`).
 */
export const destroyByPublicId = async (
  publicId: string,
  resourceType: 'image' | 'raw',
): Promise<boolean> => {
  if (!isCloudinaryUploadsEnabled()) return false;
  ensureConfigured();
  return new Promise((resolve, reject) => {
    cloudinary.uploader.destroy(publicId, { resource_type: resourceType }, (err, result) => {
      if (err != null) {
        reject(err);
        return;
      }
      const r = result as { result?: string } | undefined;
      resolve(r?.result === 'ok');
    });
  });
};

/**
 * Try to delete a Cloudinary asset when local file is missing.
 * Use the same path segment you stored as `filePath` in API responses (full public_id).
 */
export const tryDestroyIfCloudinary = async (
  publicIdOrRelativePath: string,
  resourceType: 'image' | 'raw',
): Promise<boolean> => {
  if (!isCloudinaryUploadsEnabled()) return false;
  const id = publicIdOrRelativePath.trim();
  if (id.length === 0) return false;
  try {
    return await destroyByPublicId(id, resourceType);
  } catch {
    return false;
  }
};
