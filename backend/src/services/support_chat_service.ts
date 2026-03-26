import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';

export type SupportConversationStatus = 'open' | 'closed';
export type SupportConversationLastSenderType = 'user' | 'admin';

let _supportSchemaEnsured = false;

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

const ensureSupportChatSchema = async (): Promise<void> => {
  if (_supportSchemaEnsured) return;

  const pool = getPool();

  // Create base tables if missing.
  // NOTE: We intentionally keep this logic in the backend so local/dev/prod
  // environments stay consistent even if a SQL migration wasn’t run.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS support_conversations (
      id              VARCHAR(50)  PRIMARY KEY,
      user_id         VARCHAR(50)  NOT NULL,
      status          ENUM('open','closed') NOT NULL DEFAULT 'open',
      created_at      TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at      TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      last_message_at TIMESTAMP    NULL,
      last_message_preview VARCHAR(255) NULL,
      last_message_sender_type ENUM('user','admin') NULL,
      CONSTRAINT fk_support_conv_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE KEY uniq_support_user (user_id),
      KEY idx_support_status (status),
      KEY idx_support_last_message (last_message_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS support_messages (
      id              VARCHAR(50)  PRIMARY KEY,
      conversation_id VARCHAR(50)  NOT NULL,
      sender_type     ENUM('user','admin') NOT NULL,
      sender_user_id  VARCHAR(50)  NULL,
      sender_admin_id VARCHAR(50)  NULL,
      body            TEXT         NOT NULL,
      attachment_url  VARCHAR(500) NULL,
      attachment_type ENUM('image','file') NULL,
      attachment_mime VARCHAR(255) NULL,
      attachment_filename VARCHAR(255) NULL,
      created_at      TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_support_msg_conv
        FOREIGN KEY (conversation_id) REFERENCES support_conversations(id) ON DELETE CASCADE,
      CONSTRAINT fk_support_msg_user
        FOREIGN KEY (sender_user_id) REFERENCES users(id) ON DELETE SET NULL,
      CONSTRAINT fk_support_msg_admin
        FOREIGN KEY (sender_admin_id) REFERENCES admins(id) ON DELETE SET NULL,
      KEY idx_support_msg_conv_created (conversation_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);

  // If a partially-created table exists, ensure the columns we rely on are present.
  // We do NOT use "IF NOT EXISTS" here because some MySQL setups reject it.
  if (!(await columnExists('support_conversations', 'last_message_at'))) {
    await pool.query(`ALTER TABLE support_conversations ADD COLUMN last_message_at TIMESTAMP NULL`);
  }
  if (!(await columnExists('support_conversations', 'last_message_preview'))) {
    await pool.query(
      `ALTER TABLE support_conversations ADD COLUMN last_message_preview VARCHAR(255) NULL`,
    );
  }
  if (!(await columnExists('support_conversations', 'last_message_sender_type'))) {
    await pool.query(
      `ALTER TABLE support_conversations ADD COLUMN last_message_sender_type ENUM('user','admin') NULL`,
    );
  }
  if (!(await columnExists('support_conversations', 'status'))) {
    await pool.query(
      `ALTER TABLE support_conversations ADD COLUMN status ENUM('open','closed') NOT NULL DEFAULT 'open'`,
    );
  }

  // Attachment columns for support messages.
  if (!(await columnExists('support_messages', 'attachment_url'))) {
    await pool.query(`ALTER TABLE support_messages ADD COLUMN attachment_url VARCHAR(500) NULL`);
  }
  if (!(await columnExists('support_messages', 'attachment_type'))) {
    await pool.query(
      `ALTER TABLE support_messages ADD COLUMN attachment_type ENUM('image','file') NULL`,
    );
  }
  if (!(await columnExists('support_messages', 'attachment_mime'))) {
    await pool.query(`ALTER TABLE support_messages ADD COLUMN attachment_mime VARCHAR(255) NULL`);
  }
  if (!(await columnExists('support_messages', 'attachment_filename'))) {
    await pool.query(
      `ALTER TABLE support_messages ADD COLUMN attachment_filename VARCHAR(255) NULL`,
    );
  }

  _supportSchemaEnsured = true;
};

type SupportConversationRow = RowDataPacket & {
  readonly id: string;
  readonly user_id: string;
  readonly status: SupportConversationStatus;
  readonly created_at: Date;
  readonly updated_at: Date;
  readonly last_message_at: Date | null;
  readonly last_message_preview: string | null;
  readonly last_message_sender_type: SupportConversationLastSenderType | null;
};

export type SupportConversation = {
  readonly id: string;
  readonly userId: string;
  readonly status: SupportConversationStatus;
  readonly createdAt: Date;
  readonly updatedAt: Date;
  readonly lastMessageAt?: Date;
  readonly lastMessagePreview?: string;
  readonly lastMessageSenderType?: SupportConversationLastSenderType;
};

type SupportMessageRow = RowDataPacket & {
  readonly id: string;
  readonly conversation_id: string;
  readonly sender_type: 'user' | 'admin';
  readonly sender_user_id: string | null;
  readonly sender_admin_id: string | null;
  readonly body: string;
  readonly attachment_url: string | null;
  readonly attachment_type: 'image' | 'file' | null;
  readonly attachment_mime: string | null;
  readonly attachment_filename: string | null;
  readonly created_at: Date;
};

export type SupportMessage = {
  readonly id: string;
  readonly conversationId: string;
  readonly senderType: 'user' | 'admin';
  readonly senderUserId?: string;
  readonly senderAdminId?: string;
  readonly body: string;
  readonly attachmentUrl?: string;
  readonly attachmentType?: 'image' | 'file';
  readonly attachmentMime?: string;
  readonly attachmentFilename?: string;
  readonly createdAt: Date;
};

const mapConversation = (row: SupportConversationRow): SupportConversation => ({
  id: row.id,
  userId: row.user_id,
  status: row.status,
  createdAt: row.created_at ?? new Date(),
  updatedAt: row.updated_at ?? new Date(),
  lastMessageAt: row.last_message_at ?? undefined,
  lastMessagePreview: row.last_message_preview ?? undefined,
  lastMessageSenderType: row.last_message_sender_type ?? undefined,
});

const mapMessage = (row: SupportMessageRow): SupportMessage => ({
  id: row.id,
  conversationId: row.conversation_id,
  senderType: row.sender_type,
  senderUserId: row.sender_user_id ?? undefined,
  senderAdminId: row.sender_admin_id ?? undefined,
  body: row.body,
  attachmentUrl: row.attachment_url ?? undefined,
  attachmentType: row.attachment_type ?? undefined,
  attachmentMime: row.attachment_mime ?? undefined,
  attachmentFilename: row.attachment_filename ?? undefined,
  createdAt: row.created_at ?? new Date(),
});

export const getOrCreateConversationForUser = async (userId: string): Promise<SupportConversation> => {
  await ensureSupportChatSchema();
  const pool = getPool();

  const [existingRows] = await pool.query<SupportConversationRow[]>(
    `
    SELECT *
    FROM support_conversations
    WHERE user_id = ?
    LIMIT 1
    `,
    [userId],
  );

  if (existingRows.length > 0) {
    return mapConversation(existingRows[0]);
  }

  const id = generateId('sc');
  await pool.query(
    `
    INSERT INTO support_conversations (id, user_id, status, created_at, updated_at)
    VALUES (?, ?, 'open', NOW(), NOW())
    `,
    [id, userId],
  );

  const [rows] = await pool.query<SupportConversationRow[]>(
    'SELECT * FROM support_conversations WHERE id = ?',
    [id],
  );
  if (rows.length === 0) {
    throw new Error('Failed to create support conversation');
  }
  return mapConversation(rows[0]);
};

export const listConversationsForAdmin = async (
  status?: SupportConversationStatus,
): Promise<SupportConversation[]> => {
  await ensureSupportChatSchema();
  const pool = getPool();
  const params: unknown[] = [];
  let sql = `
    SELECT *
    FROM support_conversations
  `;
  if (status) {
    sql += ' WHERE status = ?';
    params.push(status);
  }
  sql += ' ORDER BY last_message_at DESC, created_at DESC';

  const [rows] = await pool.query<SupportConversationRow[]>(sql, params);
  return rows.map(mapConversation);
};

export const getConversationById = async (id: string): Promise<SupportConversation | null> => {
  await ensureSupportChatSchema();
  const pool = getPool();
  const [rows] = await pool.query<SupportConversationRow[]>(
    'SELECT * FROM support_conversations WHERE id = ?',
    [id],
  );
  if (rows.length === 0) return null;
  return mapConversation(rows[0]);
};

export const listMessagesForConversation = async (
  conversationId: string,
  limit = 50,
  before?: Date,
): Promise<SupportMessage[]> => {
  await ensureSupportChatSchema();
  const pool = getPool();
  const params: unknown[] = [conversationId];
  let sql = `
    SELECT *
    FROM support_messages
    WHERE conversation_id = ?
  `;
  if (before) {
    sql += ' AND created_at < ?';
    params.push(before);
  }
  sql += ' ORDER BY created_at DESC LIMIT ?';
  params.push(limit);

  const [rows] = await pool.query<SupportMessageRow[]>(sql, params);
  return rows.reverse().map(mapMessage);
};

export type CreateSupportMessageInput = {
  readonly conversationId: string;
  readonly senderType: 'user' | 'admin';
  readonly senderUserId?: string;
  readonly senderAdminId?: string;
  readonly body: string;
  readonly attachmentUrl?: string;
  readonly attachmentType?: 'image' | 'file';
  readonly attachmentMime?: string;
  readonly attachmentFilename?: string;
};

export const createSupportMessage = async (input: CreateSupportMessageInput): Promise<SupportMessage> => {
  await ensureSupportChatSchema();
  const pool = getPool();
  const id = generateId('sm');

  const trimmedBody = input.body.trim();
  const hasAttachment = !!input.attachmentUrl;
  if (!trimmedBody && !hasAttachment) {
    throw new Error('Message body is required (or provide an attachment)');
  }

  const preview = trimmedBody || input.attachmentFilename || '';

  await pool.query(
    `
    INSERT INTO support_messages (
      id,
      conversation_id,
      sender_type,
      sender_user_id,
      sender_admin_id,
      body,
      attachment_url,
      attachment_type,
      attachment_mime,
      attachment_filename,
      created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    `,
    [
      id,
      input.conversationId,
      input.senderType,
      input.senderType === 'user' ? input.senderUserId ?? null : null,
      input.senderType === 'admin' ? input.senderAdminId ?? null : null,
      trimmedBody,
      input.attachmentUrl ?? null,
      input.attachmentType ?? null,
      input.attachmentMime ?? null,
      input.attachmentFilename ?? null,
    ],
  );

  await pool.query(
    `
    UPDATE support_conversations
    SET
      last_message_at = NOW(),
      last_message_preview = LEFT(?, 255),
      last_message_sender_type = ?,
      updated_at = NOW()
    WHERE id = ?
    `,
    [preview, input.senderType, input.conversationId],
  );

  const [rows] = await pool.query<SupportMessageRow[]>(
    'SELECT * FROM support_messages WHERE id = ?',
    [id],
  );
  if (rows.length === 0) {
    throw new Error('Failed to create support message');
  }
  return mapMessage(rows[0]);
};

export const setConversationStatus = async (
  conversationId: string,
  status: SupportConversationStatus,
): Promise<SupportConversation> => {
  await ensureSupportChatSchema();
  const pool = getPool();
  await pool.query(
    `
    UPDATE support_conversations
    SET status = ?, updated_at = NOW()
    WHERE id = ?
    `,
    [status, conversationId],
  );
  const conv = await getConversationById(conversationId);
  if (!conv) {
    throw new Error('Conversation not found');
  }
  return conv;
};

