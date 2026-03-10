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
  readonly frontend: {
    readonly url: string;
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
  frontend: {
    url: process.env.FRONTEND_URL ?? 'http://localhost:3000',
  },
};

