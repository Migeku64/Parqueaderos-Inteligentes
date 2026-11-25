// Respaldo automático de información (RF20, RNF14).
// Genera un JSON con todas las tablas y deja la copia en tres lugares:
//   1. Comprimida dentro de la base gestionada en la nube (Neon), en respaldo.contenido:
//      así se puede descargar aunque el servidor de la API se reinicie.
//   2. Como archivo en BACKUP_DIR (el disco del servidor; en Render gratuito es temporal).
//   3. Por correo a los administradores, en un .zip (si el correo está configurado):
//      una copia fuera de la nube del sistema.
import { mkdir, writeFile, readdir, unlink } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
import path from 'node:path';
import { sql } from '../db.js';
import { config } from '../config.js';
import { notify } from '../events.js';
import { emailConfig, emailEnabled, sendEmail } from './email.js';
import { zipOne } from './zip.js';
import { toXlsxBook } from './export.js';

export const BACKUP_TABLES = [
  'vivienda',
  'residente',
  'vehiculo',
  'celda',
  'ciclo',
  'asignacion',
  'cuenta_usuario',
  'movimiento_vehiculo',
  'notificacion',
  'auditoria',
];

export async function runBackup(trigger = 'automatico') {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const fileName = `respaldo-${stamp}.json`;
  try {
    const data = { generated_at: new Date().toISOString(), version: 2, tables: {} };
    for (const t of BACKUP_TABLES) {
      // row_to_json conserva los nombres reales de las columnas (en español)
      const rows = await sql`SELECT row_to_json(x) AS fila FROM ${sql(t)} x ORDER BY x.id`;
      data.tables[t] = rows.map((r) => r.fila);
    }
    const json = Buffer.from(JSON.stringify(data));
    // 1. En la base de datos (comprimido)
    const [rec] = await sql`
      INSERT INTO respaldo (nombre_archivo, tamano_bytes, estado, disparador, contenido)
      VALUES (${fileName}, ${json.length}, 'ok', ${trigger}, decode(${gzipSync(json).toString('base64')}, 'base64'))
      RETURNING id, nombre_archivo, tamano_bytes, estado, error, disparador, creado_en`;
    // 2. En el disco del servidor (si falla, el respaldo igual queda en la base)
    try {
      await mkdir(config.backupDir, { recursive: true });
      await writeFile(path.join(config.backupDir, fileName), json);
    } catch (e) {
      console.warn('[backup] no se pudo escribir en disco:', e.message);
    }
    await pruneOldBackups();
    // 3. Por correo, sin hacer esperar a quien pidió el respaldo
    if (config.backupEmail && emailEnabled()) {
      emailBackup(rec.id, fileName, json).catch((e) => console.error('[backup] correo', e));
    }
    return rec;
  } catch (err) {
    console.error('[backup] error', err);
    const [rec] = await sql`
      INSERT INTO respaldo (nombre_archivo, estado, error, disparador)
      VALUES (${fileName}, 'error', ${String(err.message || err)}, ${trigger}) RETURNING *`;
    await notify({ role: 'admin', title: 'Falló el respaldo automático', body: String(err.message || err), kind: 'alerta' }).catch(() => {});
    return rec;
  }
}

/** Envía el respaldo en un .zip a los correos de la administración (EMAIL_ADMINS). */
async function emailBackup(id, fileName, json) {
  const c = emailConfig();
  if (!c.admins.length) return;
  const zip = zipOne(fileName, json);
  const date = new Date().toLocaleDateString('es-CO', { timeZone: 'America/Bogota' });
  const text = `Respaldo del sistema del parqueadero del ${date}.\n\n`
    + 'Se adjuntan dos archivos con toda la información (residentes, vehículos, celdas, ciclos, '
    + 'asignaciones, usuarios, movimientos, notificaciones y auditoría):\n'
    + '- El .xlsx se abre con Excel y tiene una hoja por tabla, para consultarlo.\n'
    + '- El .zip contiene el respaldo técnico (JSON) para restaurar el sistema.\n'
    + 'Guárdelos en un lugar seguro.\n\n'
    + 'Mensaje automático del Sistema de Gestión de Parqueaderos Comunitarios.';
  const r = await sendEmail({
    to: c.admins.map((email) => ({ email })),
    subject: `Respaldo del parqueadero · ${date}`,
    text,
    html: `<p>${text.replace(/\n/g, '<br>')}</p>`,
    // .xlsx para leerlo en Excel y .zip con el JSON para restaurar el sistema
    attachments: [
      { name: fileName.replace(/\.json$/, '.xlsx'), content: backupToXlsx(json).toString('base64') },
      { name: fileName.replace(/\.json$/, '.zip'), content: zip.toString('base64') },
    ],
  });
  if (r.ok) await sql`UPDATE respaldo SET enviado_correo_en = now() WHERE id = ${id}`;
  else console.warn('[backup] no se pudo enviar por correo:', r.error);
}

/** Conserva solo los últimos BACKUP_KEEP respaldos (en la base y en el disco). */
async function pruneOldBackups() {
  await sql`
    UPDATE respaldo SET contenido = NULL
    WHERE contenido IS NOT NULL AND id NOT IN (
      SELECT id FROM respaldo WHERE contenido IS NOT NULL ORDER BY creado_en DESC LIMIT ${config.backupKeep})`;
  try {
    const files = (await readdir(config.backupDir)).filter((f) => f.startsWith('respaldo-') && f.endsWith('.json')).sort();
    const extra = files.length - config.backupKeep;
    for (let i = 0; i < extra; i++) await unlink(path.join(config.backupDir, files[i])).catch(() => {});
  } catch {
    /* sin carpeta de respaldos en disco */
  }
}

/** Contenido del respaldo (JSON) desde la base; null si ya no está guardado ahí. */
export async function backupContent(id) {
  // Se lee en base64 para no depender de cómo el controlador entrega los datos binarios
  const [row] = await sql`SELECT encode(contenido, 'base64') AS b64 FROM respaldo WHERE id = ${id} AND estado = 'ok'`;
  if (!row?.b64) return null;
  const { gunzipSync } = await import('node:zlib');
  return gunzipSync(Buffer.from(row.b64.replace(/\s/g, ''), 'base64'));
}

export function backupPath(fileName) {
  if (!/^respaldo-[\w-]+\.json$/.test(fileName)) return null;
  return path.join(config.backupDir, fileName);
}

// ---------------------------------------------------------------------------
// Respaldo en Excel: el mismo contenido, una hoja por tabla, para leerlo cómodamente.
// (El JSON sigue siendo el formato para restaurar el sistema.)
// ---------------------------------------------------------------------------
const SHEET_NAMES = {
  vivienda: 'Viviendas',
  residente: 'Residentes',
  vehiculo: 'Vehículos',
  celda: 'Celdas',
  ciclo: 'Ciclos',
  asignacion: 'Asignaciones',
  cuenta_usuario: 'Usuarios',
  movimiento_vehiculo: 'Entradas y salidas',
  notificacion: 'Notificaciones',
  auditoria: 'Auditoría',
};

// Columnas que no se muestran en el Excel (las contraseñas cifradas no sirven para leer)
const HIDDEN = /hash|token/i;
const ISO_DT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;

// Las columnas de la base no llevan tildes; en el Excel se muestran bien escritas
const ACCENTS = {
  numero: 'número', telefono: 'teléfono', contrasena: 'contraseña', ultimo: 'último', codigo: 'código',
  fecha_sorteo: 'fecha del sorteo', sorteo: 'sorteo', metodo: 'método', vehiculo: 'vehículo', ano: 'año',
  automatico: 'automático', tamano: 'tamaño', accion: 'acción', direccion: 'dirección', titulo: 'título',
  leida: 'leída', notificacion: 'notificación', asignacion: 'asignación', ipa: 'IPA',
};

function label(col) {
  const s = col.replace(/_id$/, '').split('_').map((w) => ACCENTS[w] ?? w).join(' ');
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** Convierte el JSON de un respaldo en un libro de Excel con una hoja por tabla. */
export function backupToXlsx(json) {
  const data = typeof json === 'string' || Buffer.isBuffer(json) ? JSON.parse(String(json)) : json;
  const when = data.generated_at ? new Date(data.generated_at) : new Date();
  const fecha = when.toLocaleString('es-CO', { timeZone: 'America/Bogota' });
  const sheets = Object.entries(data.tables || {}).map(([table, rows]) => {
    const keys = [...new Set(rows.flatMap((r) => Object.keys(r)))].filter((k) => !HIDDEN.test(k));
    const clean = rows.map((r) => Object.fromEntries(keys.map((k) => {
      const v = r[k];
      if (v && typeof v === 'object') return [k, JSON.stringify(v)];
      if (typeof v === 'string' && ISO_DT.test(v)) return [k, new Date(v)];
      return [k, v];
    })));
    return {
      title: `${SHEET_NAMES[table] || table} (${rows.length})`,
      sheetName: SHEET_NAMES[table] || table,
      note: `Respaldo del ${fecha} · tabla ${table}`,
      columns: keys.map((k) => ({ key: k, label: label(k) })),
      rows: clean,
    };
  });
  return toXlsxBook(sheets);
}
