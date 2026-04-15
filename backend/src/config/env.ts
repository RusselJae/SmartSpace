import dotenv from 'dotenv';

dotenv.config();

type EnvironmentConfig = {
  readonly appName: string;
  readonly environment: string;
  readonly debug: boolean;
  readonly port: number;
  readonly database: {
    readonly host: string;
    readonly port: number;
    readonly name: string;
    readonly username: string;
    readonly password: string;
    readonly timeout: number;
    readonly connectionLimit: number;
  };
  readonly email: {
    readonly host: string;
    readonly port: number;
    readonly secure: boolean;
    readonly username: string | undefined;
    readonly password: string | undefined;
    readonly from: string;
  };
  readonly resend: {
    readonly apiKey: string;
  };
  readonly sendgrid: {
    readonly apiKey: string;
    readonly from: string;
  };
  /** Absolute URL to a logo image for HTML emails (HTTPS recommended). */
  readonly emailBranding: {
    readonly logoUrl: string;
  };
  /** Public origin of this API (no trailing slash), e.g. https://your-app.up.railway.app — used for absolute upload URLs. */
  readonly publicApiBaseUrl: string;
  readonly frontend: {
    readonly url: string;
  };
  /** Used to serve `/.well-known/assetlinks.json` so Android App Links can open the APK from email. */
  readonly androidAppLink: {
    readonly packageName: string;
    /** SHA-256 cert fingerprints (colon hex), e.g. from Play Console or `keytool -list -v`. */
    readonly sha256CertFingerprints: readonly string[];
  };
  /** Public Facebook page URL for email footers (verification, etc.). */
  readonly brand: {
    readonly facebookUrl: string;
    /** Optional PNG/SVG URL for Facebook icon in HTML emails (https only). */
    readonly facebookIconUrl: string;
  };
  readonly paymongo: {
    /** sk_test_... or sk_live_... — never commit real keys */
    readonly secretKey: string;
    /** Webhook signing secret from PayMongo dashboard */
    readonly webhookSecret: string;
    /** Where PayMongo redirects after successful payment (must be reachable in browser) */
    readonly successUrl: string;
    /** Where PayMongo redirects if user cancels */
    readonly cancelUrl: string;
  };
  readonly firebase: {
    readonly serviceAccountJson: string;
  };
};

const parseBoolean = (value: string | undefined, fallback: boolean): boolean => {
  if (value == null) return fallback;
  return ['true', '1', 'yes'].includes(value.toLowerCase());
};

const parseNumber = (value: string | undefined, fallback: number): number => {
  if (value == null) return fallback;
  const parsed = Number(value);
  if (Number.isNaN(parsed)) return fallback;
  return parsed;
};

export const config: EnvironmentConfig = {
  appName: process.env.APP_NAME ?? 'SmartSpaceBackend',
  environment: process.env.APP_ENV ?? 'development',
  debug: parseBoolean(process.env.APP_DEBUG, true),
  port: parseNumber(process.env.PORT, 4000),
  database: {
    host: process.env.DB_HOST ?? 'localhost',
    port: parseNumber(process.env.DB_PORT, 3306),
    name: process.env.DB_NAME ?? 'smartspace_ar',
    username: process.env.DB_USERNAME ?? 'root',
    password: process.env.DB_PASSWORD ?? 'password',
    timeout: parseNumber(process.env.DB_TIMEOUT, 5),
    connectionLimit: parseNumber(process.env.DB_CONNECTION_LIMIT, 10),
  },
  email: {
    host: process.env.SMTP_HOST ?? process.env.SMTP_SERVER ?? 'smtp.gmail.com',
    port: parseNumber(process.env.SMTP_PORT, 587),
    secure: parseBoolean(process.env.SMTP_SECURE, false),
    username: process.env.SMTP_USERNAME ?? process.env.SMTP_USER,
    password: process.env.SMTP_PASSWORD ?? process.env.SMTP_PASS,
    from: process.env.SMTP_FROM ?? 'Wood Home Furniture Trading <noreply@woodhomefurniture.com>',
  },
  resend: {
    // Resend API key (works well on Railway / small hosts without SMTP)
    // Keep this as an empty string when unset so the email sender can
    // cleanly no-op with a helpful log message.
    apiKey: process.env.RESEND_API_KEY ?? '',
  },
  sendgrid: {
    apiKey: process.env.SENDGRID_API_KEY ?? '',
    // Use a dedicated SENDGRID_FROM when present; otherwise reuse SMTP_FROM
    // so existing env setups keep working.
    from:
      process.env.SENDGRID_FROM ??
      process.env.SMTP_FROM ??
      'Wood Home Furniture Trading <noreply@woodhomefurniture.com>',
  },
  emailBranding: {
    logoUrl: (process.env.EMAIL_LOGO_URL ?? '').trim(),
  },
  publicApiBaseUrl: (process.env.PUBLIC_API_BASE_URL ?? '').trim().replace(/\/+$/, ''),
  frontend: {
    url: process.env.FRONTEND_URL ?? 'http://localhost:3000',
  },
  androidAppLink: {
    packageName: (process.env.ANDROID_APP_LINK_PACKAGE_NAME ?? 'com.example.smartspace_ar').trim(),
    sha256CertFingerprints: (process.env.ANDROID_APP_LINK_SHA256_CERT_FINGERPRINTS ?? '')
      .split(/[\s,]+/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0),
  },
  brand: {
    facebookUrl: (process.env.BRAND_FACEBOOK_URL ?? 'https://www.facebook.com').trim(),
    facebookIconUrl: (
      process.env.BRAND_FACEBOOK_ICON_URL ??
      'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1b/Facebook_icon.svg/48px-Facebook_icon.svg.png'
    ).trim(),
  },
  paymongo: {
    secretKey: process.env.PAYMONGO_SECRET_KEY ?? '',
    webhookSecret: process.env.PAYMONGO_WEBHOOK_SECRET ?? '',
    // Default return URLs hit this API so test checkout works without configuring Flutter port
    successUrl:
      process.env.PAYMONGO_SUCCESS_URL ??
      `${process.env.PUBLIC_API_BASE_URL ?? 'http://localhost:4000'}/api/paymongo-return/success`,
    cancelUrl:
      process.env.PAYMONGO_CANCEL_URL ??
      `${process.env.PUBLIC_API_BASE_URL ?? 'http://localhost:4000'}/api/paymongo-return/cancel`,
  },
  firebase: {
    serviceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON ?? '',
  },
};

