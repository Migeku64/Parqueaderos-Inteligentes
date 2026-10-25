import { createServer } from './app.js';
import { config } from './config.js';
import { sql } from './db.js';
import { runBackup } from './services/backup.js';
import { notify } from './events.js';

const server = createServer();

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`\nERROR: el puerto ${config.port} ya está ocupado por otro programa (probablemente otra ventana de la API).`);
    console.error('Cierre las otras ventanas de INICIAR.bat, o ejecute en PowerShell:');
    console.error(`   netstat -ano | findstr :${config.port}     (y luego)  taskkill /PID <numero> /F\n`);
  } else {
    console.error('ERROR al iniciar el servidor:', err.message);
  }
  process.exit(1);
});

server.listen(config.port, '0.0.0.0', () => {
  console.log(`API de parqueaderos escuchando en http://0.0.0.0:${config.port}`);
  console.log(`WebSocket en ws://0.0.0.0:${config.port}/ws?token=<JWT>`);
});

// ---- Tareas programadas ----
const HOUR = 3600_000;

// Respaldo automático (RF20)
if (config.backupIntervalHours > 0) {
  setInterval(() => runBackup('automatico'), config.backupIntervalHours * HOUR).unref();
}

// Recordatorio de fin de ciclo: 7 días antes, una sola vez por ciclo (RF13)
async function cycleReminders() {
  try {
    const cycles = await sql`
      SELECT c.* FROM cycle c
      WHERE c.status = 'activo' AND c.end_date - CURRENT_DATE BETWEEN 0 AND 7
        AND NOT EXISTS (SELECT 1 FROM notification n WHERE n.kind = 'fin_ciclo_' || c.id)`;
    for (const c of cycles) {
      const rows = await sql`SELECT resident_id FROM parking_assignment WHERE cycle_id = ${c.id} AND status = 'vigente'`;
      await notify({
        residentIds: rows.map((x) => x.resident_id),
        title: 'Su ciclo de parqueadero está por terminar',
        body: `El ciclo "${c.name}" finaliza el ${c.end_date}.`,
        kind: `fin_ciclo_${c.id}`,
      });
      await notify({
        role: 'admin',
        title: `El ciclo "${c.name}" termina pronto`,
        body: `Finaliza el ${c.end_date}. Recuerde programar el próximo sorteo.`,
        kind: `fin_ciclo_${c.id}`,
      });
    }
  } catch (err) {
    console.error('[recordatorios]', err.message);
  }
}
setTimeout(cycleReminders, 10_000).unref();
setInterval(cycleReminders, 6 * HOUR).unref();

async function shutdown() {
  console.log('Cerrando servidor...');
  server.close();
  await sql.end({ timeout: 5 });
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
