// Cambia los nombres repetidos de los residentes de demostración por nombres variados, y
// los residentes de demostración que se llamaban como el equipo (Miguel, Ariadna y Julián siguen
// siendo usuarios administradores, pero ya no aparecen como residentes).
// Solo toca a los residentes que creó el script de demostración y cuyo nombre nadie ha editado;
// no cambia casas, vehículos, celdas, ciclos, asignaciones ni contraseñas.
//
// Uso (PowerShell, desde la carpeta backend):
//   $env:DATABASE_URL="postgres://...la de Neon..."; $env:DATABASE_SSL="true"; node scripts/variar_nombres.js
import { sql } from '../src/db.js';
import { demoName, oldDemoName } from './nombres_demo.js';

const BASE = 1100000000;

// Residentes de demostración con el nombre del equipo → nombre nuevo (se reconocen por documento y nombre)
const TEAM = [
  ['1012345678', 'Miguel Ángel Pinilla', 'Mauricio Salazar', 'mauricio@correo.com'],
  ['1023456789', 'Ariadna Cardona', 'Catalina Ospina', 'catalina@correo.com'],
  ['1034567890', 'Julián Montoya', 'Gustavo Quintero', 'gustavo@correo.com'],
];
const STEP = 7919;

async function main() {
  const rows = await sql`
    SELECT id, nombre_completo, numero_documento FROM residente
    WHERE numero_documento ~ '^11[0-9]{8}$'`;
  let changed = 0;
  let skipped = 0;
  let already = 0;
  let team = 0;
  await sql.begin(async (tx) => {
    for (const [doc, oldName, name, email] of TEAM) {
      const [r] = await tx`SELECT id FROM residente WHERE numero_documento = ${doc} AND nombre_completo = ${oldName}`;
      if (!r) continue;
      await tx`UPDATE residente SET nombre_completo = ${name}, correo = ${email} WHERE id = ${r.id}`;
      await tx`UPDATE cuenta_usuario SET nombre_completo = ${name} WHERE residente_id = ${r.id}`;
      team++;
    }
    for (const r of rows) {
      const n = Number(r.document_number ?? r.numero_documento) - BASE;
      if (n < 0 || n % STEP !== 0) continue;
      const i = n / STEP;
      const current = r.full_name ?? r.nombre_completo;
      if (current === demoName(i)) {
        already++; // ya tenía el nombre nuevo (el script ya se había ejecutado)
        continue;
      }
      if (current !== oldDemoName(i)) {
        skipped++; // alguien lo editó a mano: se respeta
        continue;
      }
      const name = demoName(i);
      await tx`UPDATE residente SET nombre_completo = ${name} WHERE id = ${r.id}`;
      await tx`UPDATE cuenta_usuario SET nombre_completo = ${name} WHERE residente_id = ${r.id}`;
      changed++;
    }
  });
  console.log(`Listo: ${changed} residentes con nombre nuevo.`);
  if (team) console.log(`${team} residentes que se llamaban como el equipo ahora tienen otro nombre (las cuentas admin no cambian).`);
  if (already) console.log(`${already} ya tenían el nombre nuevo.`);
  if (skipped) console.log(`${skipped} se dejaron igual porque alguien ya los había editado.`);
  await sql.end();
}

main().catch(async (e) => {
  console.error('No se pudo completar:', e.message);
  await sql.end();
  process.exit(1);
});
