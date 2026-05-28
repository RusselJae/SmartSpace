import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  getLegalContent,
  updateLegalContent,
  listLegalContentHistory,
  isValidLegalKey,
  type LegalContentKey,
} from '../services/legal_content_service';
import { logAdminActivity } from '../services/admin_activity_log_service';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS } from '../auth/admin_role';

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

    const payload = await getLegalContent(key as LegalContentKey);
    res.json({ success: true, data: payload });
  }),
);

/**
 * GET /api/content/legal/:key/history
 * Public endpoint – prior published snapshots for a legal key.
 *
 * This is intentionally read-only and does not expose admin activity logs.
 * Useful for compliance transparency so customers can view previous versions.
 */
legalContentRouter.get(
  '/legal/:key/history',
  asyncHandler(async (req, res) => {
    const { key } = req.params;
    if (!isValidLegalKey(key)) {
      return res.status(400).json({
        success: false,
        message: "key must be 'terms' or 'privacy'",
      });
    }
    const limit = Number(req.query.limit ?? 40);
    const entries = await listLegalContentHistory(key as LegalContentKey, limit);
    res.json({ success: true, data: { entries } });
  }),
);

/**
 * GET /api/content/admin/legal/:key/history
 * Admin-only: prior saved versions (snapshots taken before each publish).
 */
legalContentRouter.get(
  '/admin/legal/:key/history',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.legalWrite),
  asyncHandler(async (req, res) => {
    const { key } = req.params;
    if (!isValidLegalKey(key)) {
      return res.status(400).json({
        success: false,
        message: "key must be 'terms' or 'privacy'",
      });
    }
    const limit = Number(req.query.limit ?? 40);
    const entries = await listLegalContentHistory(key as LegalContentKey, limit);
    res.json({ success: true, data: { entries } });
  }),
);

/**
 * PATCH /api/content/admin/legal/:key
 * Admin-only: update Terms & Conditions or Privacy Policy content.
 * Body: { adminId: string, content: string }
 */
legalContentRouter.patch(
  '/admin/legal/:key',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.legalWrite),
  asyncHandler(async (req, res) => {
    const { key } = req.params;
    const { content } = req.body as { content?: string };

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
    await logAdminActivity({
      adminId: req.adminAuth!.id,
      action: 'legal_content_updated',
      entityType: 'legal_content',
      entityId: key,
      details: { version: String(updated.version) },
    });
    res.json({ success: true, data: updated });
  }),
);
