// Reportes administrativos (RF08, UC-07), exportación a PDF, Excel y CSV (RF19) y dashboard (RF14).
import { sql, num } from '../db.js';
import { badRequest, toCsv } from '../http.js';
import { ADMIN, STAFF } from '../auth.js';
import { toPdf, toXlsx } from '../services/export.js';

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
      SELECT s.codigo,
             CASE WHEN NOT s.activo THEN 'inactiva' WHEN s.ocupada THEN 'ocupada'
                  WHEN a.id IS NOT NULL THEN 'asignada' ELSE 'libre' END AS state,
             r.nombre_completo AS resident_name,
             CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house,
             count(m.id) FILTER (WHERE m.tipo = 'entrada')::int AS entries,
             count(m.id) FILTER (WHERE m.tipo = 'salida')::int AS exits,
             max(m.registrado_en) AS last_movement
      FROM celda s
      LEFT JOIN LATERAL (SELECT pa.* FROM asignacion pa JOIN ciclo c ON c.id = pa.ciclo_id
                         WHERE pa.celda_id = s.id AND pa.estado = 'vigente' AND c.estado = 'activo' LIMIT 1) a ON TRUE
      LEFT JOIN residente r ON r.id = a.residente_id
      LEFT JOIN vivienda h ON h.id = r.vivienda_id
      LEFT JOIN movimiento_vehiculo m ON m.celda_id = s.id AND m.autorizado
           AND (${f.from}::date IS NULL OR m.registrado_en >= ${f.from}::date)
           AND (${f.to}::date IS NULL OR m.registrado_en < ${f.to}::date + 1)
      WHERE (${f.spot}::text IS NULL OR s.codigo = upper(${f.spot}))
      GROUP BY s.id, s.codigo, s.activo, s.ocupada, a.id, r.nombre_completo, h.bloque, h.numero
      ORDER BY length(s.codigo), s.codigo`,
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
      SELECT c.nombre, c.fecha_inicio, c.fecha_fin, c.estado,
             count(pa.id) FILTER (WHERE pa.estado <> 'cancelada')::int AS assigned,
             count(pa.id) FILTER (WHERE pa.metodo = 'sorteo' AND pa.estado <> 'cancelada')::int AS by_draw,
             count(pa.id) FILTER (WHERE pa.metodo = 'manual' AND pa.estado <> 'cancelada')::int AS manual,
             count(pa.id) FILTER (WHERE pa.estado = 'cancelada')::int AS cancelled,
             count(pa.id) FILTER (WHERE pa.estado <> 'cancelada' AND EXISTS (
                 SELECT 1 FROM asignacion p2 JOIN ciclo c2 ON c2.id = p2.ciclo_id
                 WHERE p2.residente_id = pa.residente_id AND p2.estado <> 'cancelada'
                   AND c2.fecha_inicio = (SELECT max(c3.fecha_inicio) FROM ciclo c3 WHERE c3.fecha_inicio < c.fecha_inicio)))::int AS repeated,
             (SELECT count(*)::int FROM movimiento_vehiculo m WHERE NOT m.autorizado
                AND m.registrado_en >= c.fecha_inicio AND m.registrado_en < c.fecha_fin + 1) AS unauthorized
      FROM ciclo c LEFT JOIN asignacion pa ON pa.ciclo_id = c.id
      WHERE (${f.from}::date IS NULL OR c.fecha_fin >= ${f.from}::date)
        AND (${f.to}::date IS NULL OR c.fecha_inicio <= ${f.to}::date)
      GROUP BY c.id ORDER BY c.fecha_inicio DESC`,
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
      SELECT c.nombre AS cycle_name, s.codigo AS spot_code, r.nombre_completo,
             CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house,
             v.placa, pa.metodo, pa.puntaje_ipa, pa.estado, pa.asignado_en, pa.liberado_en
      FROM asignacion pa
      JOIN ciclo c ON c.id = pa.ciclo_id JOIN celda s ON s.id = pa.celda_id
      JOIN residente r ON r.id = pa.residente_id JOIN vivienda h ON h.id = r.vivienda_id
      JOIN vehiculo v ON v.id = pa.vehiculo_id
      WHERE (${f.from}::date IS NULL OR c.fecha_fin >= ${f.from}::date)
        AND (${f.to}::date IS NULL OR c.fecha_inicio <= ${f.to}::date)
        AND (${f.spot}::text IS NULL OR s.codigo = upper(${f.spot}))
        AND (${f.resident_id}::int IS NULL OR r.id = ${f.resident_id}::int)
      ORDER BY c.fecha_inicio DESC, length(s.codigo), s.codigo`,
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
      SELECT m.registrado_en, m.tipo, m.placa, r.nombre_completo AS resident_name, s.codigo AS spot_code,
             CASE WHEN m.autorizado THEN 'Sí' ELSE 'No' END AS autorizado, m.motivo, m.origen,
             ua.usuario AS registrado_por
      FROM movimiento_vehiculo m
      LEFT JOIN vehiculo v ON v.id = m.vehiculo_id LEFT JOIN residente r ON r.id = v.residente_id
      LEFT JOIN celda s ON s.id = m.celda_id
      LEFT JOIN cuenta_usuario ua ON ua.id = m.registrado_por
      WHERE (${f.from}::date IS NULL OR m.registrado_en >= ${f.from}::date)
        AND (${f.to}::date IS NULL OR m.registrado_en < ${f.to}::date + 1)
        AND (${f.spot}::text IS NULL OR s.codigo = upper(${f.spot}))
        AND (${f.resident_id}::int IS NULL OR r.id = ${f.resident_id}::int)
      ORDER BY m.registrado_en DESC LIMIT 5000`,
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
    const base = `reporte-${ctx.params.type}-${new Date().toISOString().slice(0, 10)}`;
    const exporters = {
      csv: () => [toCsv(rows, rep.columns), 'text/csv; charset=utf-8'],
      pdf: () => [toPdf({ title: rep.title, columns: rep.columns, rows, filters: f }), 'application/pdf'],
      xlsx: () => [
        toXlsx({ title: rep.title, columns: rep.columns, rows, filters: f }),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
    };
    if (q.format) {
      const make = exporters[q.format];
      if (!make) throw badRequest('Formato inválido (use pdf, xlsx o csv)');
      const [body, type] = make();
      ctx.send(200, body, type, { 'Content-Disposition': `attachment; filename="${base}.${q.format}"` });
      return;
    }
    return { type: ctx.params.type, title: rep.title, columns: rep.columns, filters: f, rows };
  });

  r.get('/dashboard', STAFF, async () => {
    const [spots] = await sql`
      SELECT count(*) FILTER (WHERE activo)::int AS total,
             count(*) FILTER (WHERE activo AND ocupada)::int AS occupied,
             count(*) FILTER (WHERE activo AND NOT ocupada)::int AS free,
             count(*) FILTER (WHERE activo AND para_discapacidad)::int AS disabled_spots
      FROM celda`;
    const [active] = await sql`
      SELECT c.*, (SELECT count(*)::int FROM asignacion pa WHERE pa.ciclo_id = c.id AND pa.estado = 'vigente') AS assigned
      FROM ciclo c WHERE c.estado = 'activo'`;
    const [next] = await sql`SELECT * FROM ciclo WHERE estado = 'planeado' ORDER BY fecha_inicio LIMIT 1`;
    const [residents] = await sql`
      SELECT count(*) FILTER (WHERE estado = 'activo')::int AS active,
             count(*) FILTER (WHERE estado = 'activo' AND deuda > 0)::int AS with_debt
      FROM residente`;
    const [today] = await sql`
      SELECT count(*) FILTER (WHERE tipo = 'entrada' AND autorizado)::int AS entries,
             count(*) FILTER (WHERE tipo = 'salida')::int AS exits,
             count(*) FILTER (WHERE NOT autorizado)::int AS rejected
      FROM movimiento_vehiculo WHERE registrado_en >= CURRENT_DATE`;
    const recent = await sql`
      SELECT m.id, m.placa, m.tipo, m.autorizado, m.motivo, m.registrado_en, s.codigo AS spot_code
      FROM movimiento_vehiculo m LEFT JOIN celda s ON s.id = m.celda_id
      ORDER BY m.registrado_en DESC, m.id DESC LIMIT 10`;
    const byDay = await sql`
      SELECT d::date AS day,
             (SELECT count(*)::int FROM movimiento_vehiculo m
               WHERE m.tipo = 'entrada' AND m.autorizado AND m.registrado_en >= d AND m.registrado_en < d + interval '1 day') AS entries
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
