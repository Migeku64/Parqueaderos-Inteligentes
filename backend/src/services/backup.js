// Respaldo automático de información (RF20, RNF14).
// Genera un archivo JSON con todas las tablas en BACKUP_DIR y registra el resultado.
// Para producción se recomienda además el respaldo nativo del proveedor cloud o pg_dump.
import { mkdir, writeFile, readdir, unlink, stat } from 'node:fs/promises';
import path from 'node:path';
import { sql } from '../db.js';
import { config } from '../config.js';
import { notify } from '../events.js';

export const BACKUP_TABLES = [
  'house',
  'resident',
  'vehicle',
  'parking_spot',
  'cycle',
  'parking_assignment',
  'user_account',
  'vehicle_movement',
  'notification',
  'audit_log',
];

export async function runBackup(trigger = 'automatico') {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const fileName = `respaldo-${stamp}.json`;
  try {
    await mkdir(config.backupDir, { recursive: true });
    const data = { generated_at: new Date().toISOString(), version: 1, tables: {} };
    for (const t of BACKUP_TABLES) {
      data.tables[t] = await sql`SELECT * FROM ${sql(t)} ORDER BY id`;
    }
    const file = path.join(config.backupDir, fileName);
    await writeFile(file, JSON.stringify(data));
    const { size } = await stat(file);
    const [rec] = await sql`
      INSERT INTO backup_record (file_name, size_bytes, status, trigger)
      VALUES (${fileName}, ${size}, 'ok', ${trigger}) RETURNING *`;
    await pruneOldBackups();
    return rec;
  } catch (err) {
    console.error('[backup] error', err);
    const [rec] = await sql`
      INSERT INTO backup_record (file_name, status, error, trigger)
      VALUES (${fileName}, 'error', ${String(err.message || err)}, ${trigger}) RETURNING *`;
    await notify({ role: 'admin', title: 'Falló el respaldo automático', body: String(err.message || err), kind: 'alerta' }).catch(() => {});
    return rec;
  }
}

async function pruneOldBackups() {
  const files = (await readdir(config.backupDir)).filter((f) => f.startsWith('respaldo-') && f.endsWith('.json')).sort();
  const extra = files.length - config.backupKeep;
  for (let i = 0; i < extra; i++) await unlink(path.join(config.backupDir, files[i])).catch(() => {});
}

export function backupPath(fileName) {
  if (!/^respaldo-[\w-]+\.json$/.test(fileName)) return null;
  return path.join(config.backupDir, fileName);
}
