import { Application } from 'express';

import { config } from '../config/env';

/**
 * Serves Digital Asset Links for Android App Links.
 * Email verification uses https://{PUBLIC_API_BASE_URL}/api/users/verify-email?... — when this file
 * validates, tapping that link on Android can open the installed app instead of the browser.
 */
export function registerWellKnownRoutes(app: Application): void {
  app.get('/.well-known/assetlinks.json', (_req, res) => {
    const packageName = config.androidAppLink.packageName;
    const fingerprints = config.androidAppLink.sha256CertFingerprints;

    if (!packageName || fingerprints.length === 0) {
      res
        .status(404)
        .type('application/json')
        .send(JSON.stringify({ message: 'Configure ANDROID_APP_LINK_PACKAGE_NAME and ANDROID_APP_LINK_SHA256_CERT_FINGERPRINTS' }));
      return;
    }

    res.type('application/json').json([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: packageName,
          sha256_cert_fingerprints: [...fingerprints],
        },
      },
    ]);
  });
}
