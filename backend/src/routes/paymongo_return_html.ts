/**
 * Shared HTML for PayMongo return URLs: redirects into the Flutter app via custom scheme.
 * Fallback copy + manual link if the OS does not auto-open the app.
 */

export const buildPaymongoAppReturnUrl = (params: {
  readonly status: 'success' | 'cancel';
  readonly orderId?: string;
  readonly mtoRequestId?: string;
}): string => {
  const q = new URLSearchParams();
  q.set('status', params.status);
  if (params.orderId) q.set('orderId', params.orderId);
  if (params.mtoRequestId) q.set('mtoRequestId', params.mtoRequestId);
  return `smartspace://paymongo-return?${q.toString()}`;
};

/** Single-page redirect: meta refresh + JS + visible link (no external images). */
export const paymongoReturnRedirectPage = (appUrl: string, title: string, bodyLine: string): string => {
  const safeApp = appUrl.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  const safeAppJs = JSON.stringify(appUrl);
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta http-equiv="refresh" content="0;url=${safeApp}"/>
  <title>${title}</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; padding: 2rem; line-height: 1.5; color: #333; max-width: 420px; margin: 0 auto; text-align: center; }
    a.btn { display: inline-block; margin-top: 1rem; padding: 14px 24px; background: #5C4033; color: #fff; text-decoration: none; border-radius: 4px; font-weight: 600; }
    p.note { color: #666; font-size: 14px; margin-top: 1.5rem; }
  </style>
</head>
<body>
  <h1>${title}</h1>
  <p>${bodyLine}</p>
  <p><a class="btn" href="${safeApp}">Return to Wood Home app</a></p>
  <p class="note">If nothing happens, tap the button above.</p>
  <script>
    (function () {
      var u = ${safeAppJs};
      try { window.location.replace(u); } catch (e) {}
      setTimeout(function () { try { window.location.href = u; } catch (e2) {} }, 400);
    })();
  </script>
</body>
</html>`;
};
