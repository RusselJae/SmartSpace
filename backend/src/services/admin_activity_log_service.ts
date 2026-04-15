import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { generateId } from '../utils/id_generator';

type AdminActivityRow = RowDataPacket & {
  readonly id: string;
  readonly admin_id: string | null;
  readonly action: string;
  readonly entity_type: string;
  readonly entity_id: string | null;
  readonly details_json: string | null;
  readonly created_at: Date;
  readonly admin_email: string | null;
  readonly admin_full_name: string | null;
};

export type AdminActivityLogItem = {
  readonly id: string;
  readonly adminId: string | null;
  readonly action: string;
  readonly entityType: string;
  readonly entityId: string | null;
  readonly details: Record<string, string>;
  readonly createdAt: Date;
  readonly adminEmail: string | null;
  readonly adminFullName: string | null;
};

let _schemaEnsured = false;

const ensureSchema = async (): Promise<void> => {
  if (_schemaEnsured) return;
  const pool = getPool();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS admin_activity_logs (
      id VARCHAR(64) PRIMARY KEY,
      admin_id VARCHAR(64) NULL,
      action VARCHAR(80) NOT NULL,
      entity_type VARCHAR(80) NOT NULL,
      entity_id VARCHAR(80) NULL,
      details_json JSON NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_admin_activity_created (created_at),
      INDEX idx_admin_activity_admin (admin_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
  `);
  _schemaEnsured = true;
};

export const logAdminActivity = async (params: {
  readonly adminId?: string | null;
  readonly action: string;
  readonly entityType: string;
  readonly entityId?: string | null;
  readonly details?: Record<string, string>;
}): Promise<void> => {
  await ensureSchema();
  const pool = getPool();
  const id = generateId('aal');
  await pool.query(
    `INSERT INTO admin_activity_logs (id, admin_id, action, entity_type, entity_id, details_json)
     VALUES (?, ?, ?, ?, ?, CAST(? AS JSON))`,
    [
      id,
      params.adminId ?? null,
      params.action,
      params.entityType,
      params.entityId ?? null,
      JSON.stringify(params.details ?? {}),
    ],
  );
};

export type ListAdminActivityLogFilters = {
  readonly limit?: number;
  readonly adminId?: string;
  readonly action?: string;
  readonly from?: Date;
  readonly to?: Date;
};

export const listAdminActivityLogs = async (
  filters: ListAdminActivityLogFilters = {},
): Promise<AdminActivityLogItem[]> => {
  await ensureSchema();
  const pool = getPool();
  const where: string[] = [];
  const params: unknown[] = [];
  if (filters.adminId != null && filters.adminId.trim().length > 0) {
    where.push('l.admin_id = ?');
    params.push(filters.adminId.trim());
  }
  if (filters.action != null && filters.action.trim().length > 0) {
    where.push('l.action = ?');
    params.push(filters.action.trim());
  }
  if (filters.from != null) {
    where.push('l.created_at >= ?');
    params.push(filters.from);
  }
  if (filters.to != null) {
    where.push('l.created_at <= ?');
    params.push(filters.to);
  }
  const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
  const limit = Math.min(Math.max(filters.limit ?? 50, 1), 500);
  const [rows] = await pool.query<AdminActivityRow[]>(
    `SELECT
        l.*,
        a.email AS admin_email,
        a.full_name AS admin_full_name
     FROM admin_activity_logs l
     LEFT JOIN admins a ON a.id = l.admin_id
     ${whereClause}
     ORDER BY l.created_at DESC
     LIMIT ?`,
    [...params, limit],
  );
  return rows.map((row) => ({
    id: row.id,
    adminId: row.admin_id ?? null,
    action: row.action,
    entityType: row.entity_type,
    entityId: row.entity_id ?? null,
    details: row.details_json ? (JSON.parse(row.details_json) as Record<string, string>) : {},
    createdAt: row.created_at ?? new Date(),
    adminEmail: row.admin_email ?? null,
    adminFullName: row.admin_full_name ?? null,
  }));
};

