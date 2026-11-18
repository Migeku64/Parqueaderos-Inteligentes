// Ejecución del sorteo real (manual o automático) y sorteos programados por fecha.
import { sql } from '../db.js';
import { config } from '../config.js';
import { audit, notify } from '../events.js';
import { broadcast } from '../ws.js';
import { confirmDraw } from './draw.js';
import { spotsChanged } from '../routes/spots.js';

/**
 * Ejecuta el sorteo real de un ciclo: guarda las asignaciones, registra la auditoría
 * y notifica a los residentes. Lo usan el botón del administrador y el sorteo automático.
 * @param {{cycleId:number, mode?:string, proposal?:any[], userId?:number|null, automatic?:boolean}} o
 */
export async function runDraw({ cycleId, mode = 'ponderado', proposal, userId = null, automatic = false }) {
  const result = await sql.begin(async (tx) => {
    const res = await confirmDraw(tx, cycleId, { mode, proposal });
    await audit(tx, userId, automatic ? 'sorteo_automatico' : 'sorteo', 'ciclo', cycleId, {
      modo: res.mode,
      automatico: automatic,
      asignados: res.assigned.length,
      lista_espera: res.waitlist.length,
      resultado: res.assigned.map((a) => ({ residente: a.full_name, celda: a.spot_code, ipa: a.ipa })),
    });
    for (const a of res.assigned) {
      await notify(
        {
          residentIds: [a.resident_id],
          title: '¡Resultado del sorteo: le fue asignada una celda!',
          body: `Celda ${a.spot_code} para el vehículo ${a.plate} en el ciclo "${res.cycle.name}" (${res.cycle.start_date} a ${res.cycle.end_date}).`,
          kind: 'sorteo',
        },
        tx,
      );
    }
    if (res.waitlist.length) {
      await notify(
        {
          residentIds: res.waitlist.map((w) => w.resident_id),
          title: 'Resultado del sorteo: lista de espera',
          body: `En el ciclo "${res.cycle.name}" no alcanzó celda. Su tiempo de espera aumentará su prioridad en el próximo sorteo.`,
          kind: 'sorteo',
        },
        tx,
      );
    }
    if (automatic) {
      await notify(
        {
          role: 'admin',
          title: `Se realizó el sorteo automático del ciclo "${res.cycle.name}"`,
          body: `${res.assigned.length} celdas asignadas y ${res.waitlist.length} residentes en lista de espera. Puede revisar el resultado en "Ciclos y sorteos".`,
          kind: 'sorteo',
        },
        tx,
      );
    }
    return res;
  });
  broadcast('assignments', { cycle_id: cycleId });
  spotsChanged();
  return result;
}

/**
 * Busca los ciclos con sorteo automático cuya fecha y hora ya llegaron (hora de Colombia)
 * y ejecuta el sorteo real. Cada ciclo se sortea una sola vez.
 */
export async function runScheduledDraws() {
  const due = await sql`
    SELECT c.id, c.nombre FROM ciclo c
    WHERE c.estado = 'planeado'
      AND c.sorteo_automatico
      AND c.fecha_sorteo IS NOT NULL
      AND c.sorteo_ejecutado_en IS NULL
      AND (now() AT TIME ZONE ${config.timezone}) >= c.fecha_sorteo + make_interval(hours => ${config.autoDrawHour})
      AND NOT EXISTS (SELECT 1 FROM asignacion a WHERE a.ciclo_id = c.id AND a.metodo = 'sorteo' AND a.estado <> 'cancelada')
    ORDER BY c.fecha_sorteo`;
  const done = [];
  for (const c of due) {
    try {
      const res = await runDraw({ cycleId: c.id, mode: 'ponderado', automatic: true });
      console.log(`[sorteo automático] ciclo "${c.name}": ${res.assigned.length} asignados`);
      done.push({ cycle_id: c.id, assigned: res.assigned.length });
    } catch (err) {
      console.error(`[sorteo automático] ciclo "${c.name}":`, err.message);
      // Avisa al administrador una sola vez por ciclo
      const kind = `sorteo_auto_error_${c.id}`;
      const [ya] = await sql`SELECT 1 FROM notificacion WHERE categoria = ${kind} LIMIT 1`;
      if (!ya) {
        await notify({
          role: 'admin',
          title: `No se pudo hacer el sorteo automático del ciclo "${c.name}"`,
          body: `Motivo: ${err.message}. Puede hacerlo manualmente desde "Ciclos y sorteos".`,
          kind,
        });
      }
    }
  }
  return done;
}
