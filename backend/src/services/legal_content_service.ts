import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';

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
      updated_at  TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  _legalSchemaEnsured = true;
};

const VALID_KEYS: LegalContentKey[] = ['terms', 'privacy'];

export const isValidLegalKey = (key: string): key is LegalContentKey =>
  VALID_KEYS.includes(key as LegalContentKey);

type LegalContentRow = RowDataPacket & {
  readonly key: string;
  readonly content: string | null;
  readonly updated_at: Date | null;
};

/**
 * Gets the content for a legal page (terms or privacy).
 * Returns null if not set (client should fall back to default/hardcoded content).
 */
export const getLegalContent = async (key: LegalContentKey): Promise<string | null> => {
  await ensureLegalContentSchema();
  const pool = getPool();
  const [rows] = await pool.query<LegalContentRow[]>(
    `SELECT \`key\`, content, updated_at FROM legal_content WHERE \`key\` = ?`,
    [key],
  );
  const row = rows?.[0];
  return row?.content ?? null;
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
    `INSERT INTO legal_content (\`key\`, content) VALUES (?, ?)
     ON DUPLICATE KEY UPDATE content = VALUES(content)`,
    [key, content],
  );
};
