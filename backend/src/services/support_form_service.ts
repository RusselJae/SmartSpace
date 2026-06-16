import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';
import {
  buildSupportFormLink,
  getSupportFormDefinition,
  SUPPORT_FORM_CATALOG,
} from '../support/support_form_catalog';
import { createSupportMessage, getOrCreateConversationForUser, getConversationById, updateConversationTags } from './support_chat_service';

/** Auto-applied internal tags when staff sends a structured form. */
const FORM_TYPE_TAG_MAP: Record<string, string> = {
  custom_quote: 'Made-to-order inquiry',
  order_issue: 'Order status',
  delivery_change: 'Delivery issue',
  damage_claim: 'Damage report',
};

const applyAutoTagForSentForm = async (conversationId: string, formType: string): Promise<void> => {
  const tag = FORM_TYPE_TAG_MAP[formType];
  if (!tag) return;
  const conv = await getConversationById(conversationId);
  if (!conv) return;
  const existing = [...(conv.tags ?? [])];
  if (existing.includes(tag)) return;
  await updateConversationTags(conversationId, [...existing, tag]);
};

let _schemaEnsured = false;

const ensureSchema = async (): Promise<void> => {
  if (_schemaEnsured) return;
  const pool = getPool();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS support_form_requests (
      id                  VARCHAR(50) PRIMARY KEY,
      conversation_id     VARCHAR(50) NOT NULL,
      user_id             VARCHAR(50) NOT NULL,
      form_type           VARCHAR(64) NOT NULL,
      status              ENUM('pending','submitted') NOT NULL DEFAULT 'pending',
      payload_json        JSON NULL,
      created_by_admin_id VARCHAR(50) NULL,
      created_at          TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      submitted_at        TIMESTAMP NULL,
      KEY idx_sfr_conversation (conversation_id),
      KEY idx_sfr_user (user_id),
      KEY idx_sfr_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
  _schemaEnsured = true;
};

type FormRequestRow = RowDataPacket & {
  readonly id: string;
  readonly conversation_id: string;
  readonly user_id: string;
  readonly form_type: string;
  readonly status: 'pending' | 'submitted';
  readonly payload_json: string | Record<string, unknown> | null;
  readonly created_by_admin_id: string | null;
  readonly created_at: Date;
  readonly submitted_at: Date | null;
};

export type SupportFormRequest = {
  readonly id: string;
  readonly conversationId: string;
  readonly userId: string;
  readonly formType: string;
  readonly status: 'pending' | 'submitted';
  readonly payload: Record<string, string> | null;
  readonly createdByAdminId: string | null;
  readonly createdAt: Date;
  readonly submittedAt: Date | null;
  readonly formLink: string;
};

const parsePayload = (raw: FormRequestRow['payload_json']): Record<string, string> | null => {
  if (raw == null) return null;
  if (typeof raw === 'object' && !Array.isArray(raw)) {
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(raw)) {
      out[k] = v == null ? '' : String(v);
    }
    return out;
  }
  try {
    const parsed = JSON.parse(String(raw)) as Record<string, unknown>;
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed)) {
      out[k] = v == null ? '' : String(v);
    }
    return out;
  } catch {
    return null;
  }
};

const rowToRequest = (row: FormRequestRow): SupportFormRequest => ({
  id: row.id,
  conversationId: row.conversation_id,
  userId: row.user_id,
  formType: row.form_type,
  status: row.status,
  payload: parsePayload(row.payload_json),
  createdByAdminId: row.created_by_admin_id,
  createdAt: row.created_at,
  submittedAt: row.submitted_at,
  formLink: buildSupportFormLink(row.form_type, row.id),
});

export const listSupportFormCatalog = () => SUPPORT_FORM_CATALOG;

export const getSupportFormRequestById = async (id: string): Promise<SupportFormRequest | null> => {
  await ensureSchema();
  const pool = getPool();
  const [rows] = await pool.query<FormRequestRow[]>(
    `SELECT id, conversation_id, user_id, form_type, status, payload_json,
            created_by_admin_id, created_at, submitted_at
     FROM support_form_requests WHERE id = ?`,
    [id],
  );
  const row = rows?.[0];
  return row ? rowToRequest(row) : null;
};

export const createSupportFormRequestForUser = async (input: {
  userId: string;
  formType: string;
  conversationId?: string;
}): Promise<SupportFormRequest> => {
  await ensureSchema();
  const def = getSupportFormDefinition(input.formType);
  if (!def) throw new Error('Unknown form type');

  const pool = getPool();
  let conversationId = (input.conversationId ?? '').trim();
  if (!conversationId) {
    const conv = await getOrCreateConversationForUser(input.userId);
    conversationId = conv.id;
  }

  const id = generateId('sfr');
  await pool.query(
    `INSERT INTO support_form_requests (id, conversation_id, user_id, form_type, status)
     VALUES (?, ?, ?, ?, 'pending')`,
    [id, conversationId, input.userId, def.type],
  );

  const created = await getSupportFormRequestById(id);
  if (!created) throw new Error('Failed to create form request');
  return created;
};

export const sendSupportFormLinkAsAdmin = async (input: {
  conversationId: string;
  userId: string;
  formType: string;
  adminId: string;
}): Promise<{
  request: SupportFormRequest;
  messageId: string;
  message: Awaited<ReturnType<typeof createSupportMessage>>;
  conversation?: Awaited<ReturnType<typeof getConversationById>>;
}> => {
  const def = getSupportFormDefinition(input.formType);
  if (!def) throw new Error('Unknown form type');

  await ensureSchema();
  const pool = getPool();
  const id = generateId('sfr');
  await pool.query(
    `INSERT INTO support_form_requests
      (id, conversation_id, user_id, form_type, status, created_by_admin_id)
     VALUES (?, ?, ?, ?, 'pending', ?)`,
    [id, input.conversationId, input.userId, def.type, input.adminId],
  );

  const request = await getSupportFormRequestById(id);
  if (!request) throw new Error('Failed to create form request');

  const link = buildSupportFormLink(def.type, id);
  // Compact marker keeps chat readable; UI renders a form card instead of boilerplate.
  const body = `[form-card]\n${link}`;

  const message = await createSupportMessage({
    conversationId: input.conversationId,
    senderType: 'admin',
    senderAdminId: input.adminId,
    body,
  });

  await applyAutoTagForSentForm(input.conversationId, def.type);
  const conversation = await getConversationById(input.conversationId);

  return { request, messageId: message.id, message, conversation: conversation ?? undefined };
};

export const submitSupportFormRequest = async (input: {
  requestId: string;
  userId: string;
  payload: Record<string, string>;
}): Promise<SupportFormRequest> => {
  await ensureSchema();
  const existing = await getSupportFormRequestById(input.requestId);
  if (!existing) throw new Error('Form request not found');
  if (existing.userId !== input.userId) throw new Error('Forbidden');
  if (existing.status === 'submitted') throw new Error('This form was already submitted');

  const def = getSupportFormDefinition(existing.formType);
  if (!def) throw new Error('Unknown form type');

  for (const field of def.fields) {
    if (field.required) {
      const v = (input.payload[field.key] ?? '').trim();
      if (!v) throw new Error(`${field.label} is required`);
    }
  }

  const pool = getPool();
  await pool.query(
    `UPDATE support_form_requests
     SET status = 'submitted', payload_json = ?, submitted_at = CURRENT_TIMESTAMP
     WHERE id = ?`,
    [JSON.stringify(input.payload), input.requestId],
  );

  const defTitle = def.title;
  const summaryLines = def.fields
    .map((f) => {
      const v = (input.payload[f.key] ?? '').trim();
      if (!v) return null;
      return `• ${f.label}: ${v}`;
    })
    .filter((line): line is string => line != null);

  await createSupportMessage({
    conversationId: existing.conversationId,
    senderType: 'user',
    senderUserId: input.userId,
    body: `Submitted form: ${defTitle}\n${summaryLines.join('\n')}`,
  });

  const updated = await getSupportFormRequestById(input.requestId);
  if (!updated) throw new Error('Failed to load submission');
  return updated;
};

export const listFormRequestsForConversation = async (
  conversationId: string,
): Promise<SupportFormRequest[]> => {
  await ensureSchema();
  const pool = getPool();
  const [rows] = await pool.query<FormRequestRow[]>(
    `SELECT id, conversation_id, user_id, form_type, status, payload_json,
            created_by_admin_id, created_at, submitted_at
     FROM support_form_requests
     WHERE conversation_id = ?
     ORDER BY created_at DESC`,
    [conversationId],
  );
  return (rows ?? []).map(rowToRequest);
};
