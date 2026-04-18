/**
 * Strong password rules for admin accounts and password-reset flows.
 * Kept in one place so API routes and services stay consistent.
 */

export const STRONG_PASSWORD_MESSAGE =
  'Password must be at least 12 characters and include uppercase, lowercase, a number, and a symbol.';

const SPECIAL_RE = /[!@#$%^&*()_+\-=[\]{};':"\\|,.<>/?]/;

/**
 * Validates password strength; throws Error with STRONG_PASSWORD_MESSAGE if invalid.
 */
export const assertStrongPassword = (raw: string): void => {
  const password = (raw ?? '').trim();
  if (password.length < 12) {
    throw new Error(STRONG_PASSWORD_MESSAGE);
  }
  if (!/[A-Z]/.test(password)) {
    throw new Error(STRONG_PASSWORD_MESSAGE);
  }
  if (!/[a-z]/.test(password)) {
    throw new Error(STRONG_PASSWORD_MESSAGE);
  }
  if (!/[0-9]/.test(password)) {
    throw new Error(STRONG_PASSWORD_MESSAGE);
  }
  if (!SPECIAL_RE.test(password)) {
    throw new Error(STRONG_PASSWORD_MESSAGE);
  }
};
