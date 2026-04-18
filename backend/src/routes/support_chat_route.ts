import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { asyncHandler } from '../utils/async_handler';
import { uploadsRoot } from '../utils/uploads';
import {
  createSupportMessage,
  listConversationsForAdmin,
  listMessagesForConversation,
  setConversationStatus,
  getOrCreateConversationForUser,
  getConversationById,
  resolveCanonicalUserIdForSupport,
} from '../services/support_chat_service';
import {
  isCloudinaryUploadsEnabled,
  uploadImageBuffer,
  uploadRawBuffer,
} from '../services/cloudinary_service';
import { isSupabaseStorageEnabled, uploadToSupabaseStorage } from '../services/supabase_storage_service';
import { shouldUseMemoryBufferUpload } from '../services/storage_mode';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS } from '../auth/admin_role';

export const supportChatRouter = Router();

// -----------------------------------------------------------------------------
// Support chat attachment uploads
// - Local: uploads/support-chat/<conversationId>/ → /uploads/support-chat/...
// - Supabase / Cloudinary: same path prefix under remote storage → https URL
// -----------------------------------------------------------------------------

const supportChatAttachmentStorage = multer.diskStorage({
  destination: (req, _file, cb) => {
    const conversationId = (req.params.id as string) || 'default';
    const safeConversationId = conversationId.replace(/[^a-zA-Z0-9_-]/g, '') || 'default';

    const dir = path.join(uploadsRoot, 'support-chat', safeConversationId);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    cb(null, dir);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '';
    const base = path.basename(file.originalname, ext).replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 80);
    const timestamp = Date.now();
    const rand = Math.floor(Math.random() * 1000000).toString().padStart(6, '0');
    cb(null, `${base}_${timestamp}_${rand}${ext}`);
  },
});

const supportChatAttachmentUpload = multer({
  storage: shouldUseMemoryBufferUpload() ? multer.memoryStorage() : supportChatAttachmentStorage,
  limits: {
    fileSize: 15 * 1024 * 1024, // 15MB max attachment
  },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();

    const allowedImageExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
    const allowedDocExts = [
      '.pdf',
      '.txt',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.zip',
      '.rar',
    ];

    // Allow based on extension primarily (client mimetype can be unreliable).
    if (allowedImageExts.includes(ext)) {
      return cb(null, true);
    }
    if (allowedDocExts.includes(ext)) {
      return cb(null, true);
    }

    cb(
      new Error(
        `Invalid attachment type. Allowed images (${allowedImageExts.join(', ')}) and docs (${allowedDocExts.join(', ')})`,
      ),
    );
  },
});

/** Build stored attachment URL (relative /uploads/..., Supabase, or Cloudinary https URL). */
const buildSupportAttachmentUrl = async (
  file: Express.Multer.File,
  conversationId: string,
): Promise<string> => {
  const safeConversationId = conversationId.replace(/[^a-zA-Z0-9_-]/g, '') || 'default';
  const ext = path.extname(file.originalname) || '';
  const base = path
    .basename(file.originalname, ext)
    .replace(/[^a-zA-Z0-9_-]/g, '_')
    .substring(0, 80);
  const timestamp = Date.now();
  const rand = Math.floor(Math.random() * 1000000)
    .toString()
    .padStart(6, '0');
  const fileName = `${base}_${timestamp}_${rand}${ext}`;
  const subFolder = `support-chat/${safeConversationId}`;

  const allowedImageExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
  const isImage = allowedImageExts.includes(ext.toLowerCase());

  if (isSupabaseStorageEnabled()) {
    const contentType =
      isImage && file.mimetype && file.mimetype.startsWith('image/')
        ? file.mimetype
        : file.mimetype && file.mimetype.length > 0
          ? file.mimetype
          : 'application/octet-stream';
    const { publicUrl } = await uploadToSupabaseStorage({
      subKey: `${subFolder}/${fileName}`,
      buffer: file.buffer,
      contentType,
    });
    return publicUrl;
  }

  if (isCloudinaryUploadsEnabled()) {
    const buffer = file.buffer;
    if (isImage) {
      const { secureUrl } = await uploadImageBuffer({
        subFolder: subFolder,
        fileName,
        buffer,
      });
      return secureUrl;
    }
    const { secureUrl } = await uploadRawBuffer({
      subFolder: subFolder,
      fileName,
      buffer,
      mimeType: file.mimetype,
    });
    return secureUrl;
  }

  return `/uploads/support-chat/${safeConversationId}/${file.filename}`;
};

supportChatRouter.post(
  '/user/conversation',
  asyncHandler(async (req, res) => {
    const { userId, email } = req.body as { userId?: string; email?: string };

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'userId is required',
      });
    }

    const resolved = await resolveCanonicalUserIdForSupport(userId, email);
    if (!resolved.ok) {
      return res.status(400).json({ success: false, message: resolved.message });
    }

    const conversation = await getOrCreateConversationForUser(resolved.userId);
    res.json({ success: true, data: conversation });
  }),
);

supportChatRouter.get(
  '/user/conversation/:id/messages',
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { before, limit } = req.query as { before?: string; limit?: string };

    const parsedBefore = before ? new Date(before) : undefined;
    const parsedLimit = limit != null ? Math.min(Number(limit) || 50, 100) : 50;

    const messages = await listMessagesForConversation(id, parsedLimit, parsedBefore);
    res.json({ success: true, data: messages });
  }),
);

supportChatRouter.post(
  '/user/conversation/:id/messages',
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { userId, email, body } = req.body as { userId?: string; email?: string; body?: string };

    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    if (!body || !body.trim()) {
      return res.status(400).json({ success: false, message: 'Message body is required' });
    }

    const conv = await getConversationById(id);
    if (!conv) {
      return res.status(404).json({ success: false, message: 'Conversation not found' });
    }
    const resolved = await resolveCanonicalUserIdForSupport(userId, email);
    if (!resolved.ok) {
      return res.status(400).json({ success: false, message: resolved.message });
    }
    if (conv.userId !== resolved.userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }

    const message = await createSupportMessage({
      conversationId: id,
      senderType: 'user',
      senderUserId: resolved.userId,
      body,
    });

    res.status(201).json({ success: true, data: message });
  }),
);

// User: send message with attachment (image or file)
supportChatRouter.post(
  '/user/conversation/:id/messages/attachment',
  supportChatAttachmentUpload.single('attachment'),
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { userId, email, body } = req.body as { userId?: string; email?: string; body?: string };

    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'attachment file is required' });
    }

    const conv = await getConversationById(id);
    if (!conv) {
      return res.status(404).json({ success: false, message: 'Conversation not found' });
    }
    const resolved = await resolveCanonicalUserIdForSupport(userId, email);
    if (!resolved.ok) {
      return res.status(400).json({ success: false, message: resolved.message });
    }
    if (conv.userId !== resolved.userId) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }

    const conversationId = id;
    const attachmentUrl = await buildSupportAttachmentUrl(req.file, conversationId);
    const fileExt = path.extname(req.file.originalname).toLowerCase();
    const attachmentType: 'image' | 'file' = ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(fileExt)
      ? 'image'
      : 'file';

    const message = await createSupportMessage({
      conversationId,
      senderType: 'user',
      senderUserId: resolved.userId,
      body: body ?? '',
      attachmentUrl,
      attachmentType,
      attachmentMime: req.file.mimetype,
      attachmentFilename: req.file.originalname,
    });

    res.status(201).json({ success: true, data: message });
  }),
);

supportChatRouter.get(
  '/admin/conversations',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.supportWrite),
  asyncHandler(async (req, res) => {
    const { status } = req.query as { status?: string };
    const statusFilter =
      status === 'open' || status === 'closed' ? (status as 'open' | 'closed') : undefined;

    const conversations = await listConversationsForAdmin(statusFilter);
    res.json({ success: true, data: conversations });
  }),
);

supportChatRouter.get(
  '/admin/conversation/:id/messages',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.supportWrite),
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { before, limit } = req.query as { before?: string; limit?: string };
    const parsedBefore = before ? new Date(before) : undefined;
    const parsedLimit = limit != null ? Math.min(Number(limit) || 50, 100) : 50;

    const messages = await listMessagesForConversation(id, parsedLimit, parsedBefore);
    res.json({ success: true, data: messages });
  }),
);

supportChatRouter.post(
  '/admin/conversation/:id/messages',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.supportWrite),
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { body } = req.body as { body?: string };

    if (!body || !body.trim()) {
      return res.status(400).json({ success: false, message: 'Message body is required' });
    }

    const message = await createSupportMessage({
      conversationId: id,
      senderType: 'admin',
      senderAdminId: req.adminAuth!.id,
      body,
    });

    res.status(201).json({ success: true, data: message });
  }),
);

// Admin: send message with attachment (image or file)
supportChatRouter.post(
  '/admin/conversation/:id/messages/attachment',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.supportWrite),
  supportChatAttachmentUpload.single('attachment'),
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { body } = req.body as { body?: string };

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'attachment file is required' });
    }

    const conversationId = id;
    const attachmentUrl = await buildSupportAttachmentUrl(req.file, conversationId);
    const fileExt = path.extname(req.file.originalname).toLowerCase();
    const attachmentType: 'image' | 'file' = ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(fileExt)
      ? 'image'
      : 'file';

    const message = await createSupportMessage({
      conversationId,
      senderType: 'admin',
      senderAdminId: req.adminAuth!.id,
      body: body ?? '',
      attachmentUrl,
      attachmentType,
      attachmentMime: req.file.mimetype,
      attachmentFilename: req.file.originalname,
    });

    res.status(201).json({ success: true, data: message });
  }),
);

supportChatRouter.patch(
  '/admin/conversation/:id/status',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.supportWrite),
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { status } = req.body as { status?: string };

    if (status !== 'open' && status !== 'closed') {
      return res.status(400).json({
        success: false,
        message: "status must be 'open' or 'closed'",
      });
    }

    const conversation = await setConversationStatus(id, status);
    res.json({ success: true, data: conversation });
  }),
);

