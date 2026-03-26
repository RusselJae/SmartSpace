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
} from '../services/support_chat_service';

export const supportChatRouter = Router();

// -----------------------------------------------------------------------------
// Support chat attachment uploads
// - Stores files under: uploads/support-chat/<conversationId>/
// - Returns a relative download URL like: /uploads/support-chat/<id>/<filename>
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
  storage: supportChatAttachmentStorage,
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

supportChatRouter.post(
  '/user/conversation',
  asyncHandler(async (req, res) => {
    const { userId } = req.body as { userId?: string };

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'userId is required',
      });
    }

    const conversation = await getOrCreateConversationForUser(userId);
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
    const { userId, body } = req.body as { userId?: string; body?: string };

    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    if (!body || !body.trim()) {
      return res.status(400).json({ success: false, message: 'Message body is required' });
    }

    const message = await createSupportMessage({
      conversationId: id,
      senderType: 'user',
      senderUserId: userId,
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
    const { userId, body } = req.body as { userId?: string; body?: string };

    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'attachment file is required' });
    }

    const conversationId = id;
    const attachmentUrl = `/uploads/support-chat/${conversationId}/${req.file.filename}`;
    const fileExt = path.extname(req.file.originalname).toLowerCase();
    const attachmentType: 'image' | 'file' = ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(fileExt)
      ? 'image'
      : 'file';

    const message = await createSupportMessage({
      conversationId,
      senderType: 'user',
      senderUserId: userId,
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
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { adminId, body } = req.body as { adminId?: string; body?: string };

    if (!adminId) {
      return res.status(400).json({ success: false, message: 'adminId is required' });
    }
    if (!body || !body.trim()) {
      return res.status(400).json({ success: false, message: 'Message body is required' });
    }

    const message = await createSupportMessage({
      conversationId: id,
      senderType: 'admin',
      senderAdminId: adminId,
      body,
    });

    res.status(201).json({ success: true, data: message });
  }),
);

// Admin: send message with attachment (image or file)
supportChatRouter.post(
  '/admin/conversation/:id/messages/attachment',
  supportChatAttachmentUpload.single('attachment'),
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { adminId, body } = req.body as { adminId?: string; body?: string };

    if (!adminId) {
      return res.status(400).json({ success: false, message: 'adminId is required' });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'attachment file is required' });
    }

    const conversationId = id;
    const attachmentUrl = `/uploads/support-chat/${conversationId}/${req.file.filename}`;
    const fileExt = path.extname(req.file.originalname).toLowerCase();
    const attachmentType: 'image' | 'file' = ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(fileExt)
      ? 'image'
      : 'file';

    const message = await createSupportMessage({
      conversationId,
      senderType: 'admin',
      senderAdminId: adminId,
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

