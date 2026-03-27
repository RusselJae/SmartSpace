import { Router } from 'express';
import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { asyncHandler } from '../utils/async_handler';

export const settingsRouter = Router();

const ensureAppSettingsTable = async (): Promise<void> => {
  const pool = getPool();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_settings (
      id TINYINT NOT NULL PRIMARY KEY,
      payload_json LONGTEXT NOT NULL,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);
};

type SettingsRow = RowDataPacket & {
  id: number;
  payload_json: string;
};

settingsRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    await ensureAppSettingsTable();
    const pool = getPool();

    const [rows] = await pool.query<SettingsRow[]>(
      'SELECT id, payload_json FROM app_settings WHERE id = 1 LIMIT 1',
    );

    if (rows.length === 0) {
      return res.json({ success: true, data: {} });
    }

    let parsed: Record<string, unknown> = {};
    try {
      parsed = JSON.parse(rows[0].payload_json) as Record<string, unknown>;
    } catch {
      parsed = {};
    }

    return res.json({ success: true, data: parsed });
  }),
);

settingsRouter.put(
  '/',
  asyncHandler(async (req, res) => {
    await ensureAppSettingsTable();
    const pool = getPool();

    const payload = req.body;
    if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
      return res.status(400).json({ success: false, message: 'Settings payload must be an object' });
    }

    const payloadJson = JSON.stringify(payload);
    await pool.query(
      `
      INSERT INTO app_settings (id, payload_json)
      VALUES (1, ?)
      ON DUPLICATE KEY UPDATE payload_json = VALUES(payload_json), updated_at = NOW()
      `,
      [payloadJson],
    );

    return res.json({ success: true, data: payload });
  }),
);

