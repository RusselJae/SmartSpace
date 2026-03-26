import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  getLegalContent,
  updateLegalContent,
  isValidLegalKey,
  type LegalContentKey,
} from '../services/legal_content_service';

export const legalContentRouter = Router();

/**
 * GET /api/content/legal/:key
 * Public endpoint – returns the content for terms or privacy.
 * Key must be 'terms' or 'privacy'.
 * Returns { content: string | null } – null if not set (client should use default).
 */
legalContentRouter.get(
  '/legal/:key',
  asyncHandler(async (req, res) => {
    const { key } = req.params;
    if (!isValidLegalKey(key)) {
      return res.status(400).json({
        success: false,
        message: "key must be 'terms' or 'privacy'",
      });
    }

    const content = await getLegalContent(key as LegalContentKey);
    res.json({ success: true, data: { content } });
  }),
);

/**
 * PATCH /api/content/admin/legal/:key
 * Admin-only: update Terms & Conditions or Privacy Policy content.
 * Body: { adminId: string, content: string }
 */
legalContentRouter.patch(
  '/admin/legal/:key',
  asyncHandler(async (req, res) => {
    const { key } = req.params;
    const { adminId, content } = req.body as { adminId?: string; content?: string };

    if (!adminId) {
      return res.status(400).json({ success: false, message: 'adminId is required' });
    }
    if (!isValidLegalKey(key)) {
      return res.status(400).json({
        success: false,
        message: "key must be 'terms' or 'privacy'",
      });
    }
    if (content === undefined || content === null) {
      return res.status(400).json({ success: false, message: 'content is required' });
    }

    await updateLegalContent(key as LegalContentKey, String(content));
    const updated = await getLegalContent(key as LegalContentKey);
    res.json({ success: true, data: { content: updated } });
  }),
);
