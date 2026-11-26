// Cambia la deuda de los residentes de demostración que debían exactamente $85.000
// (todos tenían el mismo valor) por valores variados según las cuotas atrasadas.
// Solo toca a los residentes que creó el script de demostración y cuya deuda nadie ha cambiado.
// No cambia nombres, placas, celdas, ciclos, asignaciones ni contraseñas.
//
// Uso (PowerShell, desde la carpeta backend):
//   $env:DATABASE_URL="postgres://...la de Neon..."; $env:DATABASE_SSL="true"; node scripts/variar_deudas.js
import { sql } from '../src/db.js';
import { demoDebt, OLD_DEMO_DEBT } from './deudas_demo.js';

const BASE = 1100000000;
const STEP = 7919;

async function main() {
  const rows = await sql`
    SELECT id, numero_documento, deuda FROM residente
    WHERE numero_documento ~ '^11[0-9]{8}$' AND deuda = ${OLD_DEMO_DEBT}`;
  let changed = 0;
  const money = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 0 });
  const sample = [];
  await sql.begin(async (tx) => {
    for (const r of rows) {
      const n = Number(r.document_number ?? r.numero_documento) - BASE;
      if (n < 0 || n % STEP !== 0) continue;
      const debt = demoDebt(n / STEP);
      await tx`UPDATE residente SET deuda = ${debt}, actualizado_en = now() WHERE id = ${r.id}`;
      if (sample.length < 5) sample.push(`$${money.format(debt)}`);
      changed++;
    }
  });
  if (changed) {
    console.log(`Listo: ${changed} residentes con deuda variada (por ejemplo ${sample.join(', ')}).`);
  } else {
    console.log('No había deudas de $85.000 que cambiar (el script ya se había ejecutado).');
  }
  await sql.end();
}

main().catch(async (e) => {
  console.error('No se pudo completar:', e.message);
  await sql.end();
  process.exit(1);
});
