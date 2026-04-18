/**
 * Admin RBAC roles and permission checks.
 * Keep permission strings stable — they are referenced by route middleware and (optionally) the Flutter app.
 */

export const ADMIN_ROLES = [
  'super_admin',
  'operations_admin',
  'support_admin',
  'social_admin',
] as const;

export type AdminRole = (typeof ADMIN_ROLES)[number];

export const DEFAULT_ADMIN_ROLE: AdminRole = 'operations_admin';

export const parseAdminRole = (raw: string | null | undefined): AdminRole | null => {
  const s = (raw ?? '').trim();
  return (ADMIN_ROLES as readonly string[]).includes(s) ? (s as AdminRole) : null;
};

/** Fine-grained capability strings checked by middleware. */
export const ADMIN_PERMISSIONS = {
  productsWrite: 'products:write',
  ordersRead: 'orders:read',
  ordersWrite: 'orders:write',
  usersRead: 'users:read',
  reviewsModerate: 'reviews:moderate',
  faqsWrite: 'faqs:write',
  legalWrite: 'legal:write',
  supportWrite: 'support:write',
  notificationsSend: 'notifications:send',
  activityRead: 'activity:read',
  adminsManage: 'admins:manage',
  settingsWrite: 'settings:write',
  madeToOrderWrite: 'made_to_order:write',
} as const;

const OPS: readonly string[] = [
  ADMIN_PERMISSIONS.productsWrite,
  ADMIN_PERMISSIONS.ordersRead,
  ADMIN_PERMISSIONS.ordersWrite,
  ADMIN_PERMISSIONS.usersRead,
  ADMIN_PERMISSIONS.reviewsModerate,
  ADMIN_PERMISSIONS.faqsWrite,
  ADMIN_PERMISSIONS.legalWrite,
  ADMIN_PERMISSIONS.supportWrite,
  ADMIN_PERMISSIONS.notificationsSend,
  ADMIN_PERMISSIONS.activityRead,
  ADMIN_PERMISSIONS.madeToOrderWrite,
];

const SUPPORT: readonly string[] = [
  ADMIN_PERMISSIONS.ordersRead,
  ADMIN_PERMISSIONS.ordersWrite,
  ADMIN_PERMISSIONS.usersRead,
  ADMIN_PERMISSIONS.supportWrite,
];

const SOCIAL: readonly string[] = [
  ADMIN_PERMISSIONS.ordersRead,
  ADMIN_PERMISSIONS.reviewsModerate,
  ADMIN_PERMISSIONS.faqsWrite,
];

const ROLE_MATRIX: Record<Exclude<AdminRole, 'super_admin'>, ReadonlySet<string>> = {
  operations_admin: new Set(OPS),
  support_admin: new Set(SUPPORT),
  social_admin: new Set(SOCIAL),
};

export const adminHasPermission = (role: AdminRole, permission: string): boolean => {
  if (role === 'super_admin') return true;
  return ROLE_MATRIX[role].has(permission);
};
