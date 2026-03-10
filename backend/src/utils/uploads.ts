import fs from 'fs';
import path from 'path';

// Resolve uploads directory relative to project root, not dist folder
const projectRoot = path.resolve(__dirname, '../../');
const uploadsRoot = path.join(projectRoot, 'uploads');
const avatarsDir = path.join(uploadsRoot, 'avatars');
const modelsDir = path.join(uploadsRoot, 'models');
const imagesDir = path.join(uploadsRoot, 'images');
const paymentProofsDir = path.join(uploadsRoot, 'payment-proofs');

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
};

export { uploadsRoot, avatarsDir, modelsDir, imagesDir, paymentProofsDir, ensureUploadsDirectories };

