import mysql, { Pool, PoolOptions } from 'mysql2/promise';
import { config } from './env';

let pool: Pool | undefined;

const normalizePem = (value?: string): string | undefined => {
  if (!value) return undefined;

  // Some platforms store PEM strings with literal "\n". Convert to real newlines.
  return value.includes('\\n') ? value.replace('\\n', '\n') : value;
};

const createPoolOptions = (): PoolOptions => {
  const useSsl = process.env.DB_SSL === 'true';
  const ca = normalizePem(process.env.DB_SSL_CA);

  // TiDB Cloud expects TLS; when CA is provided, verify it.
  // If CA is missing, we still keep rejectUnauthorized=true (secure),
  // but TiDB setups typically require CA anyway.
  const ssl: PoolOptions['ssl'] | undefined = useSsl
    ? ca
      ? { ca, rejectUnauthorized: true }
      : { rejectUnauthorized: true }
    : undefined;

  return {
    host: config.database.host,
    port: config.database.port,
    user: config.database.username,
    password: config.database.password,
    database: config.database.name,

    waitForConnections: true,
    connectionLimit: config.database.connectionLimit,
    enableKeepAlive: true,
    connectTimeout: config.database.timeout * 1000,

    charset: 'utf8mb4',
    ssl,
  };
};

export const getPool = (): Pool => {
  if (pool == null) {
    pool = mysql.createPool(createPoolOptions());
  }
  return pool;
};
