// Reportes administrativos (RF08, UC-07), exportación CSV (RF19) y dashboard (RF14).
import { sql, num } from '../db.js';
import { badRequest, toCsv } from '../http.js';
import { ADMIN, STAFF } from '../auth.js';

const REPORTS = {
  // Ocupación por celda en un rango de fechas
  ocupacion: {
    title: 'Ocupación por celda',
    columns: [
      { key: 'code', label: 'Celda' },
      { key: 'state', label: 'Estado actual' },
      { key: 'resident_name', label: 'Residente asignado' },
      { key: 'house', label: 'Casa' },
      { key: 'entries', label: 'Entradas' },
      { key: 'exits', label: 'Salidas' },
      { key: 'last_movement', label: 'Último movimiento' },
    ],
    run: (f) => sql`
      SELECT s.code,
             CASE WHEN NOT s.is_active THEN 'inactiva' WHEN s.is_occupied THEN 'ocupada'
                  WHEN a.id IS NOT NULL THEN 'asignada' ELSE 'libre' END AS state,
             r.full_name AS resident_name,
             CASE WHEN h.block = '' THEN h.number ELSE h.block || '-' || h.number END AS house,
             count(m.id) FILTER (WHERE m.type = 'entrada')::int AS entries,
             count(m.id) FILTER (WHERE m.type = 'salida')::int AS exits,
             max(m.recorded_at) AS last_movement
      FROM parking_spot s
      LEFT JOIN LATERAL (SELECT pa.* FROM parking_assignment pa JOIN cycle c ON c.id = pa.cycle_id
                         WHERE pa.parking_spot_id = s.id AND pa.status = 'vigente' AND c.status = 'activo' LIMIT 1) a ON TRUE
      LEFT JOIN resident r ON r.id = a.resident_id
      LEFT JOIN house h ON h.id = r.house_id
      LEFT JOIN vehicle_movement m ON m.parking_spot_id = s.id AND m.authorized
           AND (${f.from}::date IS NULL OR m.recorded_at >= ${f.from}::date)
           AND (${f.to}::date IS NULL OR m.recorded_at < ${f.to}::date + 1)
      WHERE (${f.spot}::text IS NULL OR s.code = upper(${f.spot}))
      GROUP BY s.id, s.code, s.is_active, s.is_occupied, a.id, r.full_name, h.block, h.number
      ORDER BY length(s.code), s.code`,
  },
  // Cumplimiento de ciclos
  ciclos: {
    title: 'Cumplimiento de ciclos',
    columns: [
      { key: 'name', label: 'Ciclo' },
      { key: 'start_date', label: 'Inicio' },
      { key: 'end_date', label: 'Fin' },
      { key: 'status', label: 'Estado' },
      { key: 'assigned', label: 'Asignaciones' },
      { key: 'by_draw', label: 'Por sorteo' },
      { key: 'manual', label: 'Manuales' },
      { key: 'cancelled', label: 'Canceladas' },
      { key: 'repeated', label: 'Repitieron ciclo anterior' },
      { key: 'unauthorized', label: 'Ingresos no autorizados' },
    ],
    run: (f) => sql`
      SELECT c.name, c.start_date, c.end_date, c.status,
             count(pa.id) FILTER (WHERE pa.status <> 'cancelada')::int AS assigned,
             count(pa.id) FILTER (WHERE pa.method = 'sorteo' AND pa.status <> 'cancelada')::int AS by_draw,
             count(pa.id) FILTER (WHERE pa.method = 'manual' AND pa.status <> 'cancelada')::int AS manual,
             count(pa.id) FILTER (WHERE pa.status = 'cancelada')::int AS cancelled,
             count(pa.id) FILTER (WHERE pa.status <> 'cancelada' AND EXISTS (
                 SELECT 1 FROM parking_assignment p2 JOIN cycle c2 ON c2.id = p2.cycle_id
                 WHERE p2.resident_id = pa.resident_id AND p2.status <> 'cancelada'
                   AND c2.start_date = (SELECT max(c3.start_date) FROM cycle c3 WHERE c3.start_date < c.start_date)))::int AS repeated,
             (SELECT count(*)::int FROM vehicle_movement m WHERE NOT m.authorized
                AND m.recorded_at >= c.start_date AND m.recorded_at < c.end_date + 1) AS unauthorized
      FROM cycle c LEFT JOIN parking_assignment pa ON pa.cycle_id = c.id
      WHERE (${f.from}::date IS NULL OR c.end_date >= ${f.from}::date)
        AND (${f.to}::date IS NULL OR c.start_date <= ${f.to}::date)
      GROUP BY c.id ORDER BY c.start_date DESC`,
  },
  // Historial de asignaciones
  asignaciones: {
    title: 'Historial de asignaciones',
    columns: [
      { key: 'cycle_name', label: 'Ciclo' },
      { key: 'spot_code', label: 'Celda' },
      { key: 'full_name', label: 'Residente' },
      { key: 'house', label: 'Casa' },
      { key: 'plate', label: 'Placa' },
      { key: 'method', label: 'Método' },
      { key: 'ipa_score', label: 'IPA' },
      { key: 'status', label: 'Estado' },
      { key: 'assigned_at', label: 'Asignado' },
      { key: 'released_at', label: 'Liberado' },
    ],
    run: (f) => sql`
      SELECT c.name AS cycle_name, s.code AS spot_code, r.full_name,
             CASE WHEN h.block = '' THEN h.number ELSE h.block || '-' || h.number END AS house,
             v.plate, pa.method, pa.ipa_score, pa.status, pa.assigned_at, pa.released_at
      FROM parking_assignment pa
      JOIN cycle c ON c.id = pa.cycle_id JOIN parking_spot s ON s.id = pa.parking_spot_id
      JOIN resident r ON r.id = pa.resident_id JOIN house h ON h.id = r.house_id
      JOIN vehicle v ON v.id = pa.vehicle_id
      WHERE (${f.from}::date IS NULL OR c.end_date >= ${f.from}::date)
        AND (${f.to}::date IS NULL OR c.start_date <= ${f.to}::date)
        AND (${f.spot}::text IS NULL OR s.code = upper(${f.spot}))
        AND (${f.resident_id}::int IS NULL OR r.id = ${f.resident_id}::int)
      ORDER BY c.start_date DESC, length(s.code), s.code`,
  },
  // Entradas y salidas
  movimientos: {
    title: 'Entradas y salidas',
    columns: [
      { key: 'recorded_at', label: 'Fecha y hora' },
      { key: 'type', label: 'Tipo' },
      { key: 'plate', label: 'Placa' },
      { key: 'resident_name', label: 'Residente' },
      { key: 'spot_code', label: 'Celda' },
      { key: 'authorized', label: 'Autorizado' },
      { key: 'reason', label: 'Observación' },
      { key: 'source', label: 'Origen' },
      { key: 'recorded_by', label: 'Registró' },
    ],
    run: (f) => sql`
      SELECT m.recorded_at, m.type, m.plate, r.full_name AS resident_name, s.code AS spot_code,
             CASE WHEN m.authorized THEN 'Sí' ELSE 'No' END AS authorized, m.reason, m.source,
             ua.username AS recorded_by
      FROM vehicle_movement m
      LEFT JOIN vehicle v ON v.id = m.vehicle_id LEFT JOIN resident r ON r.id = v.resident_id
      LEFT JOIN parking_spot s ON s.id = m.parking_spot_id
      LEFT JOIN user_account ua ON ua.id = m.recorded_by
      WHERE (${f.from}::date IS NULL OR m.recorded_at >= ${f.from}::date)
        AND (${f.to}::date IS NULL OR m.recorded_at < ${f.to}::date + 1)
        AND (${f.spot}::text IS NULL OR s.code = upper(${f.spot}))
        AND (${f.resident_id}::int IS NULL OR r.id = ${f.resident_id}::int)
      ORDER BY m.recorded_at DESC LIMIT 5000`,
  },
};

export default function reportRoutes(r) {
  r.get('/reports', ADMIN, async () =>
    Object.entries(REPORTS).map(([key, rep]) => ({ key, title: rep.title, columns: rep.columns })),
  );

  r.get('/reports/:type', ADMIN, async (ctx) => {
    const rep = REPORTS[ctx.params.type];
    if (!rep) throw badRequest('Tipo de reporte inválido');
    const q = ctx.query;
    const f = {
      from: q.from || null,
      to: q.to || null,
      spot: q.spot || null,
      resident_id: q.resident_id ? Number(q.resident_id) : null,
    };
    const rows = await rep.run(f);
    if (q.format === 'csv') {
      const name = `reporte-${ctx.params.type}-${new Date().toISOString().slice(0, 10)}.csv`;
      ctx.send(200, toCsv(rows, rep.columns), 'text/csv; charset=utf-8', {
        'Content-Disposition': `attachment; filename="${name}"`,
      });
      return;
    }
    return { type: ctx.params.type, title: rep.title, columns: rep.columns, filters: f, rows };
  });

  r.get('/dashboard', STAFF, async () => {
    const [spots] = await sql`
      SELECT count(*) FILTER (WHERE is_active)::int AS total,
             count(*) FILTER (WHERE is_active AND is_occupied)::int AS occupied,
             count(*) FILTER (WHERE is_active AND NOT is_occupied)::int AS free,
             count(*) FILTER (WHERE is_active AND is_disabled_spot)::int AS disabled_spots
      FROM parking_spot`;
    const [active] = await sql`
      SELECT c.*, (SELECT count(*)::int FROM parking_assignment pa WHERE pa.cycle_id = c.id AND pa.status = 'vigente') AS assigned
      FROM cycle c WHERE c.status = 'activo'`;
    const [next] = await sql`SELECT * FROM cycle WHERE status = 'planeado' ORDER BY start_date LIMIT 1`;
    const [residents] = await sql`
      SELECT count(*) FILTER (WHERE status = 'activo')::int AS active,
             count(*) FILTER (WHERE status = 'activo' AND debt > 0)::int AS with_debt
      FROM resident`;
    const [today] = await sql`
      SELECT count(*) FILTER (WHERE type = 'entrada' AND authorized)::int AS entries,
             count(*) FILTER (WHERE type = 'salida')::int AS exits,
             count(*) FILTER (WHERE NOT authorized)::int AS rejected
      FROM vehicle_movement WHERE recorded_at >= CURRENT_DATE`;
    const recent = await sql`
      SELECT m.id, m.plate, m.type, m.authorized, m.reason, m.recorded_at, s.code AS spot_code
      FROM vehicle_movement m LEFT JOIN parking_spot s ON s.id = m.parking_spot_id
      ORDER BY m.recorded_at DESC, m.id DESC LIMIT 10`;
    const byDay = await sql`
      SELECT d::date AS day,
             (SELECT count(*)::int FROM vehicle_movement m
               WHERE m.type = 'entrada' AND m.authorized AND m.recorded_at >= d AND m.recorded_at < d + interval '1 day') AS entries
      FROM generate_series(CURRENT_DATE - 6, CURRENT_DATE, interval '1 day') d ORDER BY d`;
    return {
      spots,
      occupancy_rate: spots.total ? Math.round((spots.occupied / spots.total) * 100) : 0,
      active_cycle: active || null,
      next_cycle: next || null,
      residents,
      today,
      entries_last_7_days: byDay.map((d) => ({ day: d.day, entries: num(d.entries) })),
      recent_movements: recent,
    };
  });
}
