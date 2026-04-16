import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';
import { sendPushToTokens } from './push_service';

type UserNotificationRow = RowDataPacket & {
  readonly id: string;
  readonly user_id: string;
  readonly type: string;
  readonly title: string;
  readonly body: string;
  readonly data_json: string | null;
  readonly is_read: number | boolean;
  readonly created_at: Date;
};

type UserDeviceTokenRow = RowDataPacket & {
  readonly token: string;
};

export type UserNotificationItem = {
  readonly id: string;
  readonly userId: string;
  readonly type: string;
  readonly title: string;
  readonly body: string;
  readonly data: Record<string, string>;
  readonly isRead: boolean;
  readonly createdAt: Date;
};

let _schemaEnsured = false;

const ensureSchema = async (): Promise<void> => {
  if (_schemaEnsured) return;
  const pool = getPool();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_notifications (
      id VARCHAR(64) PRIMARY KEY,
      user_id VARCHAR(64) NOT NULL,
      type VARCHAR(64) NOT NULL,
      title VARCHAR(255) NOT NULL,
      body TEXT NOT NULL,
      data_json JSON NULL,
      is_read BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_user_notifications_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      INDEX idx_user_notifications_user_created (user_id, created_at),
      INDEX idx_user_notifications_user_read (user_id, is_read)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_device_tokens (
      id VARCHAR(64) PRIMARY KEY,
      user_id VARCHAR(64) NOT NULL,
      token VARCHAR(512) NOT NULL UNIQUE,
      platform VARCHAR(32) NOT NULL DEFAULT 'unknown',
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      CONSTRAINT fk_user_device_tokens_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      INDEX idx_user_device_tokens_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
  _schemaEnsured = true;
};

const mapItem = (row: UserNotificationRow): UserNotificationItem => ({
  id: row.id,
  userId: row.user_id,
  type: row.type,
  title: row.title,
  body: row.body,
  // MySQL JSON columns may come back as:
  // - string (JSON text)
  // - object (already parsed by driver)
  // - null
  // Handle all forms safely to avoid `"[object Object]" is not valid JSON`.
  data: (() => {
    const raw = row.data_json;
    if (raw == null) return {};
    if (typeof raw === 'string') {
      try {
        const parsed = JSON.parse(raw) as unknown;
        if (parsed != null && typeof parsed === 'object') {
          return parsed as Record<string, string>;
        }
      } catch (_) {
        return {};
      }
      return {};
    }
    if (typeof raw === 'object') {
      return raw as Record<string, string>;
    }
    return {};
  })(),
  isRead: Boolean(row.is_read),
  createdAt: row.created_at ?? new Date(),
});

export const listNotificationsForUser = async (userId: string, limit = 50): Promise<UserNotificationItem[]> => {
  await ensureSchema();
  const pool = getPool();
  const [rows] = await pool.query<UserNotificationRow[]>(
    `SELECT * FROM user_notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT ?`,
    [userId, Math.min(Math.max(limit, 1), 100)],
  );
  return rows.map(mapItem);
};

export const markNotificationRead = async (userId: string, notificationId: string): Promise<void> => {
  await ensureSchema();
  const pool = getPool();
  await pool.query(
    `UPDATE user_notifications SET is_read = TRUE WHERE user_id = ? AND id = ?`,
    [userId, notificationId],
  );
};

export const markAllNotificationsRead = async (userId: string): Promise<void> => {
  await ensureSchema();
  const pool = getPool();
  await pool.query(`UPDATE user_notifications SET is_read = TRUE WHERE user_id = ?`, [userId]);
};

export const registerUserDeviceToken = async (
  userId: string,
  token: string,
  platform: string,
): Promise<void> => {
  await ensureSchema();
  const pool = getPool();
  const id = generateId('udt');
  await pool.query(
    `INSERT INTO user_device_tokens (id, user_id, token, platform)
     VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), platform = VALUES(platform), updated_at = NOW()`,
    [id, userId, token.trim(), platform.trim() || 'unknown'],
  );
};

const sendPushToUser = async (
  userId: string,
  payload: { readonly title: string; readonly body: string; readonly data: Record<string, string> },
): Promise<void> => {
  const pool = getPool();
  const [rows] = await pool.query<UserDeviceTokenRow[]>(
    `SELECT token FROM user_device_tokens WHERE user_id = ?`,
    [userId],
  );
  await sendPushToTokens(
    rows.map((r) => r.token),
    payload,
  );
};

export const createNotificationForUser = async (params: {
  readonly userId: string;
  readonly type: string;
  readonly title: string;
  readonly body: string;
  readonly data?: Record<string, string>;
  readonly push?: boolean;
}): Promise<void> => {
  await ensureSchema();
  const pool = getPool();
  const id = generateId('un');
  const data = params.data ?? {};
  await pool.query(
    `INSERT INTO user_notifications (id, user_id, type, title, body, data_json, is_read)
     VALUES (?, ?, ?, ?, ?, CAST(? AS JSON), FALSE)`,
    [id, params.userId, params.type, params.title, params.body, JSON.stringify(data)],
  );
  if (params.push ?? true) {
    await sendPushToUser(params.userId, {
      title: params.title,
      body: params.body,
      data: { ...data, notificationType: params.type, notificationId: id },
    });
  }
};

export const createNotificationForAllUsers = async (params: {
  readonly type: string;
  readonly title: string;
  readonly body: string;
  readonly data?: Record<string, string>;
  readonly push?: boolean;
}): Promise<void> => {
  await ensureSchema();
  const pool = getPool();
  const [users] = await pool.query<RowDataPacket[]>('SELECT id FROM users');
  for (const user of users) {
    await createNotificationForUser({
      userId: String(user.id),
      type: params.type,
      title: params.title,
      body: params.body,
      data: params.data,
      push: params.push,
    });
  }
};

