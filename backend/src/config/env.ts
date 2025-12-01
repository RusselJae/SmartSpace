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
};

