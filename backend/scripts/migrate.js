// Crea la base de datos (si no existe) y las tablas.
// Con --reset borra las tablas primero (¡cuidado, elimina los datos!).
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import postgres from 'postgres';
import { sql } from '../src/db.js';
import { config } from '../src/config.js';

const reset = process.argv.includes('--reset');

export function explainDbError(err) {
  if (err?.code === '28P01') {
    return 'La contraseña de PostgreSQL es incorrecta. Revise DATABASE_URL en backend/.env (la misma clave que usa en pgAdmin).';
  }
  if (err?.code === 'ECONNREFUSED') {
    return 'No hay un PostgreSQL escuchando en esa dirección/puerto. Verifique que el servicio "postgresql" esté iniciado (Servicios de Windows) y el puerto en DATABASE_URL (normalmente 5432).';
  }
  if (err?.code === '3D000') return 'La base de datos no existe y no se pudo crear automáticamente. Créela en pgAdmin con el nombre "parqueadero".';
  return err?.message || String(err);
}

async function ensureDatabase() {
  const url = new URL(config.databaseUrl);
  const dbName = decodeURIComponent(url.pathname.replace(/^\//, '')) || 'parqueadero';
  url.pathname = '/postgres';
  const admin = postgres(url.toString(), { max: 1, ssl: config.databaseSsl ? 'require' : false, onnotice: () => {} });
  try {
    const rows = await admin`SELECT 1 FROM pg_database WHERE datname = ${dbName}`;
    if (!rows.length) {
      await admin.unsafe(`CREATE DATABASE "${dbName.replace(/"/g, '""')}"`);
      console.log(`Base de datos "${dbName}" creada.`);
    }
  } catch (err) {
    // En servicios en la nube puede no haber permiso para crear bases: se continúa con la existente.
    if (err?.code === '28P01' || err?.code === 'ECONNREFUSED') throw err;
  } finally {
    await admin.end();
  }
}

try {
  await ensureDatabase();
  if (reset) {
    await sql.unsafe(`
      DROP TABLE IF EXISTS backup_record, audit_log, notification, vehicle_movement, user_account,
        parking_assignment, cycle, parking_spot, vehicle, resident, house CASCADE`);
    console.log('Tablas eliminadas.');
  }
  const schema = await readFile(path.join(config.root, 'db', 'schema.sql'), 'utf8');
  await sql.begin((tx) => tx.unsafe(schema));
  console.log('Esquema aplicado correctamente.');
} catch (err) {
  console.error('ERROR:', explainDbError(err));
  process.exitCode = 1;
} finally {
  await sql.end();
}
