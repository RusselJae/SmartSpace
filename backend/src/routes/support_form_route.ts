import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../utils/async_handler';
import {
  createSupportFormRequestForUser,
  getSupportFormRequestById,
  listFormRequestsForConversation,
  listSupportFormCatalog,
  sendSupportFormLinkAsAdmin,
  submitSupportFormRequest,
} from '../services/support_form_service';
import {
  getConversationById,
  resolveCanonicalUserIdForSupport,
} from '../services/support_chat_service';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS } from '../auth/admin_role';

export const supportFormRouter = Router();

supportFormRouter.get(
  '/catalog',
  asyncHandler(async (_req, res) => {
    res.json({ success: true, data: listSupportFormCatalog() });
  }),
);

supportFormRouter.get(
  '/requests/:id',
  asyncHandler(async (req, res) => {
    const request = await getSupportFormRequestById(req.params.id);
    if (!request) {
      return res.status(404).json({ success: false, message: 'Form request not found' });
    }
    const { userId, email } = req.query as { userId?: string; email?: string };
    if (userId?.trim()) {
      const resolved = await resolveCanonicalUserIdForSupport(userId, email);
      if (!resolved.ok) {
        return res.status(400).json({ success: false, message: resolved.message });
      }
      if (request.userId !== resolved.userId) {
        return res.status(403).json({ success: false, message: 'Forbidden' });
      }
    }
    res.json({ success: true, data: request });
  }),
);

supportFormRouter.post(
  '/requests',
  asyncHandler(async (req, res) => {
    const { userId, email, formType, conversationId } = req.body as {
      userId?: string;
      email?: string;
      formType?: string;
      conversationId?: string;
    };
    if (!userId?.trim()) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    if (!formType?.trim()) {
      return res.status(400).json({ success: false, message: 'formType is required' });
    }
    const resolved = await resolveCanonicalUserIdForSupport(userId, email);
    if (!resolved.ok) {
      return res.status(400).json({ success: false, message: resolved.message });
    }
    const created = await createSupportFormRequestForUser({
      userId: resolved.userId,
      formType: formType.trim(),
      conversationId: conversationId?.trim() || undefined,
    });
    res.status(201).json({ success: true, data: created });
  }),
);

const payloadSchema = z.record(z.string(), z.string());

supportFormRouter.post(
  '/requests/:id/submit',
  asyncHandler(async (req, res) => {
    const { userId, email, payload } = req.body as {
      userId?: string;
      email?: string;
      payload?: Record<string, string>;
    };
    if (!userId?.trim()) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    const resolved = await resolveCanonicalUserIdForSupport(userId, email);
    if (!resolved.ok) {
      return res.status(400).json({ success: false, message: resolved.message });
    }
    const parsed = payloadSchema.parse(payload ?? {});
    const updated = await submitSupportFormRequest({
      requestId: req.params.id,
      userId: resolved.userId,
      payload: parsed,
    });
    res.json({ success: true, data: updated });
  }),
);

supportFormRouter.post(
  '/admin/send-link',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.supportWrite),
  asyncHandler(async (req, res) => {
    const { conversationId, formType } = req.body as {
      conversationId?: string;
      formType?: string;
    };
    if (!conversationId?.trim()) {
      return res.status(400).json({ success: false, message: 'conversationId is required' });
    }
    if (!formType?.trim()) {
      return res.status(400).json({ success: false, message: 'formType is required' });
    }
    const conv = await getConversationById(conversationId.trim());
    if (!conv) {
      return res.status(404).json({ success: false, message: 'Conversation not found' });
    }
    const result = await sendSupportFormLinkAsAdmin({
      conversationId: conv.id,
      userId: conv.userId,
      formType: formType.trim(),
      adminId: req.adminAuth!.id,
    });
    res.status(201).json({ success: true, data: result });
  }),
);

supportFormRouter.get(
  '/admin/conversation/:conversationId/requests',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.supportWrite),
  asyncHandler(async (req, res) => {
    const items = await listFormRequestsForConversation(req.params.conversationId);
    res.json({ success: true, data: items });
  }),
);
