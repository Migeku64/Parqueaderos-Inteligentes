// Cambia las placas de los vehículos de demostración (todas empezaban por «G») por placas
// colombianas variadas —carro: ABC123, moto: ABC12D— y les pone marca, modelo y color.
// Solo toca los vehículos que creó el script de demostración y cuya placa nadie ha editado.
// También actualiza la placa en el historial de entradas y salidas de esos vehículos.
// No cambia residentes, celdas, ciclos, asignaciones ni contraseñas.
//
// Uso (PowerShell, desde la carpeta backend):
//   $env:DATABASE_URL="postgres://...la de Neon..."; $env:DATABASE_SSL="true"; node scripts/variar_placas.js
import { sql } from '../src/db.js';
import { demoPlate, demoVehicleInfo, demoVehicleType, oldDemoPlate } from './placas_demo.js';

const BASE = 1100000000;
const STEP = 7919;

async function main() {
  const vehicles = await sql`
    SELECT v.id, v.placa, v.marca, v.modelo, v.color, r.numero_documento
    FROM vehiculo v JOIN residente r ON r.id = v.residente_id
    WHERE r.numero_documento ~ '^11[0-9]{8}$'`;

  // Vehículos de demostración con la placa vieja, en el orden en que los creó el script
  const demo = [];
  for (const v of vehicles) {
    const n = Number(v.document_number ?? v.numero_documento) - BASE;
    if (n < 0 || n % STEP !== 0) continue;
    const i = n / STEP;
    if ((v.plate ?? v.placa) === oldDemoPlate(i)) demo.push({ ...v, i });
  }
  demo.sort((a, b) => a.i - b.i);

  // Todas las placas que ya existen (menos las que se van a cambiar) para no repetir ninguna
  const all = await sql`SELECT placa FROM vehiculo`;
  const changing = new Set(demo.map((v) => v.plate ?? v.placa));
  const taken = new Set(all.map((r) => r.plate ?? r.placa).filter((p) => !changing.has(p)));

  let changed = 0;
  let moves = 0;
  await sql.begin(async (tx) => {
    for (const v of demo) {
      const type = demoVehicleType(v.i);
      const plate = demoPlate(v.i, type, taken);
      const info = demoVehicleInfo(v.i, type);
      const old = v.plate ?? v.placa;
      await tx`
        UPDATE vehiculo SET placa = ${plate}, tipo = ${type},
          marca = COALESCE(marca, ${info.brand}), modelo = COALESCE(modelo, ${info.model}),
          color = COALESCE(color, ${info.color})
        WHERE id = ${v.id}`;
      const m = await tx`
        UPDATE movimiento_vehiculo SET placa = ${plate}
        WHERE vehiculo_id = ${v.id} OR (vehiculo_id IS NULL AND placa = ${old}) RETURNING id`;
      moves += m.length;
      changed++;
    }
  });

  console.log(`Listo: ${changed} vehículos con placa nueva, marca, modelo y color.`);
  if (moves) console.log(`${moves} entradas y salidas del historial actualizadas con la placa nueva.`);
  if (!changed) console.log('No había placas viejas que cambiar (el script ya se había ejecutado).');
  await sql.end();
}

main().catch(async (e) => {
  console.error('No se pudo completar:', e.message);
  await sql.end();
  process.exit(1);
});
