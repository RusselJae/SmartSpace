import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { createNotificationForAllUsers } from './user_notification_service';

export type LegalContentKey = 'terms' | 'privacy';

let _legalSchemaEnsured = false;

type ColumnCheckRow = RowDataPacket & { readonly count: number };

const columnExists = async (tableName: string, columnName: string): Promise<boolean> => {
  const pool = getPool();
  const [rows] = await pool.query<ColumnCheckRow[]>(
    `
    SELECT COUNT(*) as count
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = ?
      AND column_name = ?
    `,
    [tableName, columnName],
  );
  return (rows[0]?.count ?? 0) > 0;
};

/**
 * Ensures the legal_content table exists.
 * Keys: 'terms' (Terms & Conditions), 'privacy' (Privacy Policy).
 */
const ensureLegalContentSchema = async (): Promise<void> => {
  if (_legalSchemaEnsured) return;

  const pool = getPool();

  await pool.query(`
    CREATE TABLE IF NOT EXISTS legal_content (
      \`key\`       VARCHAR(50)  PRIMARY KEY,
      content     LONGTEXT     NULL,
      version     INT          NOT NULL DEFAULT 1,
      updated_at  TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
  if (!(await columnExists('legal_content', 'version'))) {
    await pool.query(`ALTER TABLE legal_content ADD COLUMN version INT NOT NULL DEFAULT 1`);
  }

  _legalSchemaEnsured = true;
};

const VALID_KEYS: LegalContentKey[] = ['terms', 'privacy'];

export const isValidLegalKey = (key: string): key is LegalContentKey =>
  VALID_KEYS.includes(key as LegalContentKey);

type LegalContentRow = RowDataPacket & {
  readonly key: string;
  readonly content: string | null;
  readonly version: number;
  readonly updated_at: Date | null;
};

export type LegalContentPayload = {
  readonly content: string | null;
  readonly version: number;
  readonly updatedAt: Date | null;
};

/**
 * Gets the content for a legal page (terms or privacy).
 * Returns null if not set (client should fall back to default/hardcoded content).
 */
export const getLegalContent = async (key: LegalContentKey): Promise<LegalContentPayload> => {
  await ensureLegalContentSchema();
  const pool = getPool();
  const [rows] = await pool.query<LegalContentRow[]>(
    `SELECT \`key\`, content, version, updated_at FROM legal_content WHERE \`key\` = ?`,
    [key],
  );
  const row = rows?.[0];
  return {
    content: row?.content ?? null,
    version: Number(row?.version ?? 1),
    updatedAt: row?.updated_at ?? null,
  };
};

/**
 * Updates the content for a legal page.
 */
export const updateLegalContent = async (
  key: LegalContentKey,
  content: string,
): Promise<void> => {
  await ensureLegalContentSchema();
  const pool = getPool();
  await pool.query(
    `INSERT INTO legal_content (\`key\`, content, version) VALUES (?, ?, 1)
     ON DUPLICATE KEY UPDATE content = VALUES(content), version = version + 1`,
    [key, content],
  );
  if (key === 'terms') {
    const latest = await getLegalContent('terms');
    createNotificationForAllUsers({
      type: 'terms_update',
      title: 'Terms and Conditions updated',
      body: `Please review and accept Terms v${latest.version} to continue ordering.`,
      data: { key: 'terms', version: String(latest.version) },
    }).catch((error) => {
      console.error('Failed to broadcast terms update notification:', error);
    });
  }
};
