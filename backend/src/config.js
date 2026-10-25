import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Carga sencilla de un archivo .env (sin dependencias externas)
const envFile = path.join(root, '.env');
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  }
}

const env = process.env;

/**
 * Proveedores en la nube (Neon, Supabase, Render) entregan URLs con parámetros como
 * ?sslmode=require&channel_binding=require que el cliente no necesita: se quitan y el SSL
 * se activa con DATABASE_SSL.
 */
function cleanDbUrl(raw) {
  try {
    const u = new URL(raw);
    for (const k of ['sslmode', 'channel_binding', 'pgbouncer', 'connect_timeout']) u.searchParams.delete(k);
    return u.toString();
  } catch {
    return raw;
  }
}

export const config = {
  root,
  port: Number(env.PORT || 3000),
  databaseUrl: cleanDbUrl(env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/parqueadero'),
  databaseSsl: env.DATABASE_SSL === 'true' || /sslmode=(require|verify)/.test(env.DATABASE_URL || ''),
  jwtSecret: env.JWT_SECRET || 'cambia-este-secreto-en-produccion',
  jwtHours: Number(env.JWT_EXPIRES_HOURS || 12),
  corsOrigin: env.CORS_ORIGIN || '*',
  backupDir: path.resolve(root, env.BACKUP_DIR || 'backups'),
  backupIntervalHours: Number(env.BACKUP_INTERVAL_HOURS || 24),
  backupKeep: Number(env.BACKUP_KEEP || 30),
  plateReaderKey: env.PLATE_READER_KEY || '',
  houseMin: Number(env.HOUSE_MIN || 1),
  houseMax: Number(env.HOUSE_MAX || 300),
  maxFailedLogins: Number(env.MAX_FAILED_LOGINS || 5),
  isTest: env.NODE_ENV === 'test',
};

if (!config.isTest && config.jwtSecret === 'cambia-este-secreto-en-produccion') {
  console.warn('[config] ADVERTENCIA: JWT_SECRET no está definido. Defínalo en .env antes de publicar la API.');
}
