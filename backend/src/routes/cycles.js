// Ciclos (RF17), sorteo y asignación (RF03, UC-04), historial (RF10, UC-09).
import { sql } from '../db.js';
import { badRequest, conflict, notFound, required, intParam, isDate } from '../http.js';
import { ADMIN, STAFF } from '../auth.js';
import { audit, notify } from '../events.js';
import { broadcast } from '../ws.js';
import { previewDraw, confirmDraw, getCycle, evaluateResidents } from '../services/draw.js';
import { spotsChanged } from './spots.js';

const MIN_DAYS = 28; // ~1 mes de margen; el reglamento habla de 2 a 6 meses
const MAX_DAYS = 186;

function validateDates(start, end) {
  if (!isDate(start) || !isDate(end)) throw badRequest('Fechas inválidas (formato AAAA-MM-DD)');
  const days = (Date.parse(end) - Date.parse(start)) / 86400000;
  if (days < MIN_DAYS || days > MAX_DAYS) throw badRequest('Un ciclo debe durar entre 1 y 6 meses');
}

const cycleSelect = sql`
  SELECT c.*,
         (SELECT count(*)::int FROM asignacion pa WHERE pa.ciclo_id = c.id AND pa.estado <> 'cancelada') AS assignments
  FROM ciclo c`;

export default function cycleRoutes(r) {
  r.get('/cycles', STAFF, async () => sql`${cycleSelect} ORDER BY c.fecha_inicio DESC`);

  r.get('/cycles/:id', STAFF, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [c] = await sql`${cycleSelect} WHERE c.id = ${id}`;
    if (!c) throw notFound('Ciclo no encontrado');
    const assignments = await sql`
      SELECT pa.id, pa.estado, pa.metodo, pa.puntaje_ipa, pa.asignado_en, pa.liberado_en, pa.observaciones,
             r.id AS residente_id, r.nombre_completo,
             CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house,
             v.placa, s.id AS celda_id, s.codigo AS spot_code
      FROM asignacion pa
      JOIN residente r ON r.id = pa.residente_id JOIN vivienda h ON h.id = r.vivienda_id
      JOIN vehiculo v ON v.id = pa.vehiculo_id JOIN celda s ON s.id = pa.celda_id
      WHERE pa.ciclo_id = ${id}
      ORDER BY length(s.codigo), s.codigo`;
    return { ...c, assignment_list: assignments };
  });

  r.post('/cycles', ADMIN, async (ctx) => {
    const b = ctx.body;
    required(b, ['name', 'start_date', 'end_date']);
    validateDates(b.start_date, b.end_date);
    if (b.draw_date && !isDate(b.draw_date)) throw badRequest('Fecha de sorteo inválida');
    const [overlap] = await sql`
      SELECT id, nombre FROM ciclo WHERE estado <> 'cerrado'
        AND daterange(fecha_inicio, fecha_fin) && daterange(${b.start_date}::date, ${b.end_date}::date)`;
    if (overlap) throw conflict(`Las fechas se cruzan con el ciclo "${overlap.name}"`);
    const [c] = await sql`
      INSERT INTO ciclo (nombre, fecha_inicio, fecha_fin, fecha_sorteo)
      VALUES (${b.name}, ${b.start_date}, ${b.end_date}, ${b.draw_date || null}) RETURNING *`;
    await audit(null, ctx.user.id, 'crear_ciclo', 'ciclo', c.id, b);
    if (c.draw_date) {
      await notify({
        role: 'residente',
        title: 'Nuevo sorteo programado',
        body: `El sorteo del ciclo "${c.name}" será el ${c.draw_date}. Recuerde estar al día con la administración.`,
        kind: 'sorteo',
      });
    }
    ctx.status = 201;
    return c;
  });

  r.patch('/cycles/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const c = await getCycle(id);
    if (c.status === 'cerrado') throw badRequest('No se puede editar un ciclo cerrado');
    const b = ctx.body;
    const start = b.start_date ?? c.start_date;
    const end = b.end_date ?? c.end_date;
    validateDates(start, end);
    const [u] = await sql`
      UPDATE ciclo SET nombre = ${b.name ?? c.name}, fecha_inicio = ${start}, fecha_fin = ${end},
             fecha_sorteo = ${b.draw_date !== undefined ? b.draw_date || null : c.draw_date}
      WHERE id = ${id} RETURNING *`;
    await audit(null, ctx.user.id, 'editar_ciclo', 'ciclo', id, b);
    return u;
  });

  r.post('/cycles/:id/activate', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const c = await getCycle(id);
    if (c.status !== 'planeado') throw badRequest('Solo se puede activar un ciclo planeado');
    const [active] = await sql`SELECT id, nombre FROM ciclo WHERE estado = 'activo'`;
    if (active) throw conflict(`Primero finalice el ciclo activo "${active.name}"`);
    const [u] = await sql`UPDATE ciclo SET estado = 'activo' WHERE id = ${id} RETURNING *`;
    await audit(null, ctx.user.id, 'activar_ciclo', 'ciclo', id);
    const winners = await sql`SELECT residente_id FROM asignacion WHERE ciclo_id = ${id} AND estado = 'vigente'`;
    await notify({
      residentIds: winners.map((w) => w.resident_id),
      title: 'Su turno de parqueadero comenzó',
      body: `El ciclo "${u.name}" está activo hasta el ${u.end_date}.`,
      kind: 'ciclo',
    });
    spotsChanged();
    return u;
  });

  // Finalizar ciclo: libera las asignaciones vigentes (botón "Finalizar Ciclo" del prototipo)
  r.post('/cycles/:id/close', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const c = await getCycle(id);
    if (c.status === 'cerrado') throw badRequest('El ciclo ya está cerrado');
    const result = await sql.begin(async (tx) => {
      const released = await tx`
        UPDATE asignacion SET estado = 'finalizada', liberado_en = now()
        WHERE ciclo_id = ${id} AND estado = 'vigente' RETURNING residente_id`;
      const [u] = await tx`UPDATE ciclo SET estado = 'cerrado' WHERE id = ${id} RETURNING *`;
      await audit(tx, ctx.user.id, 'cerrar_ciclo', 'ciclo', id, { liberadas: released.length });
      await notify(
        {
          residentIds: released.map((x) => x.resident_id),
          title: 'Finalizó su ciclo de parqueadero',
          body: `El ciclo "${c.name}" terminó. Por favor libere la celda asignada.`,
          kind: 'ciclo',
        },
        tx,
      );
      return { ...u, released: released.length };
    });
    spotsChanged();
    return result;
  });

  // Elegibilidad + IPA de todos los residentes para un ciclo
  r.get('/cycles/:id/eligibility', ADMIN, async (ctx) => {
    const c = await getCycle(intParam(ctx.params.id));
    const { eligible, excluded } = await evaluateResidents(c);
    return { cycle: c, eligible, excluded };
  });

  // Simulación del sorteo (no guarda nada)
  r.post('/cycles/:id/draw/preview', ADMIN, async (ctx) => {
    return previewDraw(intParam(ctx.params.id), ctx.body.mode || 'ponderado');
  });

  // Ejecuta/confirma el sorteo y guarda las asignaciones
  r.post('/cycles/:id/draw', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const result = await sql.begin(async (tx) => {
      const res = await confirmDraw(tx, id, { mode: ctx.body.mode, proposal: ctx.body.proposal });
      await audit(tx, ctx.user.id, 'sorteo', 'ciclo', id, {
        modo: res.mode,
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
      return res;
    });
    ctx.status = 201;
    broadcast('assignments', { cycle_id: id });
    spotsChanged();
    return {
      cycle: result.cycle,
      mode: result.mode,
      assigned: result.assigned,
      waitlist: result.waitlist.map((w) => ({ resident_id: w.resident_id, full_name: w.full_name, house: w.house, ipa: w.ipa })),
    };
  });

  // ---------- Asignación manual / cancelación ----------
  r.post('/assignments', ADMIN, async (ctx) => {
    const b = ctx.body;
    required(b, ['cycle_id', 'resident_id', 'parking_spot_id']);
    const c = await getCycle(Number(b.cycle_id));
    if (c.status === 'cerrado') throw badRequest('El ciclo está cerrado');
    const [veh] = b.vehicle_id
      ? await sql`SELECT id FROM vehiculo WHERE id = ${b.vehicle_id} AND residente_id = ${b.resident_id} AND activo`
      : await sql`SELECT id FROM vehiculo WHERE residente_id = ${b.resident_id} AND activo ORDER BY (tipo = 'moto'), id LIMIT 1`;
    if (!veh) throw badRequest('El residente no tiene un vehículo activo');
    const [spot] = await sql`SELECT id, activo FROM celda WHERE id = ${b.parking_spot_id}`;
    if (!spot || !spot.is_active) throw badRequest('Celda no disponible');
    const [a] = await sql`
      INSERT INTO asignacion (ciclo_id, residente_id, vehiculo_id, celda_id, metodo, observaciones)
      VALUES (${c.id}, ${b.resident_id}, ${veh.id}, ${b.parking_spot_id}, 'manual', ${b.notes || null})
      RETURNING *`;
    await audit(null, ctx.user.id, 'asignacion_manual', 'asignacion', a.id, b);
    const [s] = await sql`SELECT codigo FROM celda WHERE id = ${a.parking_spot_id}`;
    await notify({
      residentIds: [Number(b.resident_id)],
      title: 'Se le asignó una celda de parqueadero',
      body: `Celda ${s.code} en el ciclo "${c.name}".`,
      kind: 'asignacion',
    });
    broadcast('assignments', { cycle_id: c.id });
    spotsChanged();
    ctx.status = 201;
    return a;
  });

  r.post('/assignments/:id/cancel', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [a] = await sql`
      UPDATE asignacion SET estado = 'cancelada', liberado_en = now(),
             observaciones = COALESCE(${ctx.body.reason || null}, observaciones)
      WHERE id = ${id} AND estado = 'vigente' RETURNING *`;
    if (!a) throw notFound('Asignación vigente no encontrada');
    await audit(null, ctx.user.id, 'cancelar_asignacion', 'asignacion', id, { motivo: ctx.body.reason });
    await notify({
      residentIds: [a.resident_id],
      title: 'Su asignación de parqueadero fue cancelada',
      body: ctx.body.reason || 'Comuníquese con la administración para más información.',
      kind: 'asignacion',
    });
    broadcast('assignments', { cycle_id: a.cycle_id });
    spotsChanged();
    return a;
  });

  // Historial completo de asignaciones con filtros (RF10)
  r.get('/assignments', STAFF, async (ctx) => {
    const q = ctx.query;
    return sql`
      SELECT pa.id, pa.estado, pa.metodo, pa.puntaje_ipa, pa.asignado_en, pa.liberado_en,
             c.id AS ciclo_id, c.nombre AS cycle_name, c.fecha_inicio, c.fecha_fin,
             r.id AS residente_id, r.nombre_completo,
             CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house,
             v.placa, s.codigo AS spot_code
      FROM asignacion pa
      JOIN ciclo c ON c.id = pa.ciclo_id
      JOIN residente r ON r.id = pa.residente_id JOIN vivienda h ON h.id = r.vivienda_id
      JOIN vehiculo v ON v.id = pa.vehiculo_id JOIN celda s ON s.id = pa.celda_id
      WHERE (${q.cycle_id || null}::int IS NULL OR c.id = ${q.cycle_id || null}::int)
        AND (${q.resident_id || null}::int IS NULL OR r.id = ${q.resident_id || null}::int)
        AND (${q.status || null}::text IS NULL OR pa.estado = ${q.status || null})
      ORDER BY c.fecha_inicio DESC, length(s.codigo), s.codigo
      LIMIT 1000`;
  });
}
