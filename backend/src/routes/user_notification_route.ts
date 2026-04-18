import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  createNotificationForAllUsers,
  listNotificationsForUser,
  markAllNotificationsRead,
  markNotificationRead,
  registerUserDeviceToken,
} from '../services/user_notification_service';
import { logAdminActivity } from '../services/admin_activity_log_service';
import { requireAdminAuth, requireAdminPermission } from '../middleware/admin_auth_middleware';
import { ADMIN_PERMISSIONS } from '../auth/admin_role';

export const userNotificationRouter = Router();

userNotificationRouter.get(
  '/:userId',
  asyncHandler(async (req, res) => {
    const userId = String(req.params.userId ?? '').trim();
    const limit = Number(req.query.limit ?? 50);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    const items = await listNotificationsForUser(userId, limit);
    return res.json({ success: true, data: items });
  }),
);

userNotificationRouter.post(
  '/:userId/read',
  asyncHandler(async (req, res) => {
    const userId = String(req.params.userId ?? '').trim();
    const notificationId = String(req.body.notificationId ?? '').trim();
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    if (notificationId) {
      await markNotificationRead(userId, notificationId);
    } else {
      await markAllNotificationsRead(userId);
    }
    return res.json({ success: true });
  }),
);

userNotificationRouter.post(
  '/:userId/device-token',
  asyncHandler(async (req, res) => {
    const userId = String(req.params.userId ?? '').trim();
    const token = String(req.body.token ?? '').trim();
    const platform = String(req.body.platform ?? 'unknown').trim();
    if (!userId || !token) {
      return res.status(400).json({ success: false, message: 'userId and token are required' });
    }
    await registerUserDeviceToken(userId, token, platform);
    return res.json({ success: true });
  }),
);

userNotificationRouter.post(
  '/admin/broadcast',
  requireAdminAuth,
  requireAdminPermission(ADMIN_PERMISSIONS.notificationsSend),
  asyncHandler(async (req, res) => {
    const adminId = req.adminAuth!.id;
    const type = String(req.body.type ?? 'admin_broadcast').trim();
    const title = String(req.body.title ?? '').trim();
    const body = String(req.body.body ?? '').trim();
    if (!title || !body) {
      return res.status(400).json({
        success: false,
        message: 'title and body are required',
      });
    }
    await createNotificationForAllUsers({
      type,
      title,
      body,
      data: {
        source: 'admin_broadcast',
        adminId,
      },
      push: true,
    });
    await logAdminActivity({
      adminId,
      action: 'broadcast_notification_sent',
      entityType: 'notification',
      details: { type, title },
    });
    return res.json({ success: true });
  }),
);

