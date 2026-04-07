import fs from 'fs';
import path from 'path';

// Resolve uploads directory relative to project root, not dist folder.
// On Render (or any host), set UPLOADS_ROOT to a persistent disk mount so uploads
// survive deploys — e.g. UPLOADS_ROOT=/var/data/uploads (see Render "Persistent Disk").
const projectRoot = path.resolve(__dirname, '../../');
const uploadsRoot =
  process.env.UPLOADS_ROOT != null && process.env.UPLOADS_ROOT.trim() !== ''
    ? path.resolve(process.env.UPLOADS_ROOT.trim())
    : path.join(projectRoot, 'uploads');
const avatarsDir = path.join(uploadsRoot, 'avatars');
const modelsDir = path.join(uploadsRoot, 'models');
const imagesDir = path.join(uploadsRoot, 'images');
const paymentProofsDir = path.join(uploadsRoot, 'payment-proofs');
const validIdsDir = path.join(uploadsRoot, 'valid-ids');
const madeToOrderDir = path.join(uploadsRoot, 'made-to-order');

const ensureUploadsDirectories = (): void => {
  if (!fs.existsSync(uploadsRoot)) {
    fs.mkdirSync(uploadsRoot, { recursive: true });
  }
  if (!fs.existsSync(avatarsDir)) {
    fs.mkdirSync(avatarsDir, { recursive: true });
  }
  if (!fs.existsSync(modelsDir)) {
    fs.mkdirSync(modelsDir, { recursive: true });
  }
  if (!fs.existsSync(imagesDir)) {
    fs.mkdirSync(imagesDir, { recursive: true });
  }
  if (!fs.existsSync(paymentProofsDir)) {
    fs.mkdirSync(paymentProofsDir, { recursive: true });
  }
  if (!fs.existsSync(validIdsDir)) {
    fs.mkdirSync(validIdsDir, { recursive: true });
  }
  if (!fs.existsSync(madeToOrderDir)) {
    fs.mkdirSync(madeToOrderDir, { recursive: true });
  }
};

export { uploadsRoot, avatarsDir, modelsDir, imagesDir, paymentProofsDir, validIdsDir, madeToOrderDir, ensureUploadsDirectories };

