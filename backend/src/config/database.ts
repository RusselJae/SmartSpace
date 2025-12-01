import mysql, { Pool, PoolOptions } from 'mysql2/promise';
import { config } from './env';

let pool: Pool | undefined;

const createPoolOptions = (): PoolOptions => {
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
  };
};

export const getPool = (): Pool => {
  if (pool == null) {
    pool = mysql.createPool(createPoolOptions());
  }
  return pool;
};





