/** Escape text embedded in minimal HTML landing pages. */
const escapeHtml = (value: string): string =>
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

/**
 * Browser-friendly page after admin taps verify in email (same pattern as customer verify).
 */
export const buildAdminVerifyEmailLandingHtml = (ok: boolean, message: string): string => {
  const safeMessage = escapeHtml(message);
  const title = ok ? 'Email verified' : 'Verification issue';
  const accent = ok ? '#2E7D32' : '#C62828';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
</head>
<body style="margin:0;font-family:system-ui,-apple-system,sans-serif;background:#f5f0eb;color:#3e2723;">
  <div style="max-width:520px;margin:48px auto;padding:32px 28px;background:#fff;border-radius:16px;box-shadow:0 8px 32px rgba(0,0,0,.08);text-align:center;">
    <h1 style="margin:0 0 12px;font-size:22px;color:${accent};">${escapeHtml(title)}</h1>
    <p style="margin:0;font-size:16px;line-height:1.55;color:#5d4037;">${safeMessage}</p>
    <p style="margin:32px 0 0;font-size:13px;color:#a1887f;">Wood Home Furniture Trading — Admin</p>
  </div>
</body>
</html>`;
};
