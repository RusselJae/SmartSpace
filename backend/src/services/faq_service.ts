import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';

let _faqSchemaEnsured = false;

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
 * Ensures the faqs table exists and has the expected schema.
 * Runs once per process.
 */
const ensureFaqSchema = async (): Promise<void> => {
  if (_faqSchemaEnsured) return;

  const pool = getPool();

  await pool.query(`
    CREATE TABLE IF NOT EXISTS faqs (
      id          VARCHAR(50)  PRIMARY KEY,
      question    VARCHAR(500) NOT NULL,
      answer      TEXT         NOT NULL,
      sort_order  INT          NOT NULL DEFAULT 0,
      created_at  TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at  TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY idx_faq_sort (sort_order)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  if (!(await columnExists('faqs', 'sort_order'))) {
    await pool.query(`ALTER TABLE faqs ADD COLUMN sort_order INT NOT NULL DEFAULT 0`);
  }

  _faqSchemaEnsured = true;
};

type FaqRow = RowDataPacket & {
  readonly id: string;
  readonly question: string;
  readonly answer: string;
  readonly sort_order: number;
  readonly created_at: Date;
  readonly updated_at: Date;
};

export type Faq = {
  readonly id: string;
  readonly question: string;
  readonly answer: string;
  readonly sortOrder: number;
  readonly createdAt: Date;
  readonly updatedAt: Date;
};

const rowToFaq = (row: FaqRow): Faq => ({
  id: row.id,
  question: row.question,
  answer: row.answer,
  sortOrder: row.sort_order ?? 0,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

/**
 * Lists all FAQs, ordered by sort_order ascending.
 */
export const listFaqs = async (): Promise<Faq[]> => {
  await ensureFaqSchema();
  const pool = getPool();
  const [rows] = await pool.query<FaqRow[]>(
    `SELECT id, question, answer, sort_order, created_at, updated_at
     FROM faqs
     ORDER BY sort_order ASC, created_at ASC`,
  );
  return (rows ?? []).map(rowToFaq);
};

export type CreateFaqInput = {
  question: string;
  answer: string;
  sortOrder?: number;
};

/**
 * Creates a new FAQ entry.
 */
export const createFaq = async (input: CreateFaqInput): Promise<Faq> => {
  await ensureFaqSchema();
  const pool = getPool();
  const id = generateId('faq');
  const sortOrder = input.sortOrder ?? 0;

  await pool.query(
    `INSERT INTO faqs (id, question, answer, sort_order)
     VALUES (?, ?, ?, ?)`,
    [id, input.question.trim(), input.answer.trim(), sortOrder],
  );

  const [rows] = await pool.query<FaqRow[]>(
    `SELECT id, question, answer, sort_order, created_at, updated_at
     FROM faqs WHERE id = ?`,
    [id],
  );
  const row = rows?.[0];
  if (!row) throw new Error('Failed to fetch created FAQ');
  return rowToFaq(row);
};

export type UpdateFaqInput = {
  question?: string;
  answer?: string;
  sortOrder?: number;
};

/**
 * Updates an existing FAQ.
 */
export const updateFaq = async (id: string, input: UpdateFaqInput): Promise<Faq | null> => {
  await ensureFaqSchema();
  const pool = getPool();

  const [existing] = await pool.query<FaqRow[]>(`SELECT id FROM faqs WHERE id = ?`, [id]);
  if (!existing || existing.length === 0) return null;

  const updates: string[] = [];
  const values: (string | number)[] = [];

  if (input.question !== undefined) {
    updates.push('question = ?');
    values.push(input.question.trim());
  }
  if (input.answer !== undefined) {
    updates.push('answer = ?');
    values.push(input.answer.trim());
  }
  if (input.sortOrder !== undefined) {
    updates.push('sort_order = ?');
    values.push(input.sortOrder);
  }

  if (updates.length > 0) {
    values.push(id);
    await pool.query(`UPDATE faqs SET ${updates.join(', ')} WHERE id = ?`, values);
  }

  const [rows] = await pool.query<FaqRow[]>(
    `SELECT id, question, answer, sort_order, created_at, updated_at
     FROM faqs WHERE id = ?`,
    [id],
  );
  const row = rows?.[0];
  return row ? rowToFaq(row) : null;
};

/**
 * Deletes an FAQ by id.
 */
export const deleteFaq = async (id: string): Promise<boolean> => {
  await ensureFaqSchema();
  const pool = getPool();
  const [result] = await pool.query<ResultSetHeader>(`DELETE FROM faqs WHERE id = ?`, [id]);
  return (result?.affectedRows ?? 0) > 0;
};
