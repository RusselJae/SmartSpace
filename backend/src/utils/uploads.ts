import fs from 'fs';
import path from 'path';

// Resolve uploads directory relative to project root, not dist folder
const projectRoot = path.resolve(__dirname, '../../');
const uploadsRoot = path.join(projectRoot, 'uploads');
const avatarsDir = path.join(uploadsRoot, 'avatars');

const ensureUploadsDirectories = (): void => {
  if (!fs.existsSync(avatarsDir)) {
    fs.mkdirSync(avatarsDir, { recursive: true });
  }
  if (!fs.existsSync(uploadsRoot)) {
    fs.mkdirSync(uploadsRoot, { recursive: true });
  }
};

export { uploadsRoot, avatarsDir, ensureUploadsDirectories };

