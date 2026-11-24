// Celdas del parqueadero (UC-03), disponibilidad en tiempo real (RF04, RF09, RF16).
import { sql } from '../db.js';
import { badRequest, conflict, notFound, required, intParam } from '../http.js';
import { ADMIN, ANY } from '../auth.js';
import { audit } from '../events.js';
import { broadcast } from '../ws.js';

export async function listSpots(db = sql) {
  return db`
    SELECT s.id, s.codigo, s.para_discapacidad, s.activo, s.ocupada, s.observaciones,
           a.id AS asignacion_id, a.residente_id, r.nombre_completo AS resident_name,
           CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house,
           v.placa,
           CASE WHEN NOT s.activo THEN 'inactiva'
                WHEN s.ocupada THEN 'ocupada'
                WHEN a.id IS NOT NULL THEN 'asignada'
                ELSE 'libre' END AS state
    FROM celda s
    LEFT JOIN LATERAL (
      SELECT pa.* FROM asignacion pa JOIN ciclo c ON c.id = pa.ciclo_id
      WHERE pa.celda_id = s.id AND pa.estado = 'vigente' AND c.estado = 'activo' LIMIT 1
    ) a ON TRUE
    LEFT JOIN residente r ON r.id = a.residente_id
    LEFT JOIN vivienda h ON h.id = r.vivienda_id
    LEFT JOIN vehiculo v ON v.id = a.vehiculo_id
    ORDER BY length(s.codigo), s.codigo`;
}

export function spotsChanged() {
  broadcast('spots', { at: new Date().toISOString() });
}

// Códigos de un rango: { prefix: "D", from: 1, to: 50 } -> D01..D50
function rangeCodes(body) {
  const prefix = String(body.prefix ?? '').trim().toUpperCase();
  const from = Number(body.from);
  const to = Number(body.to);
  if (!Number.isInteger(from) || !Number.isInteger(to) || from < 1 || to < from || to - from > 500) {
    throw badRequest('Rango inválido');
  }
  const width = String(to).length < 2 ? 2 : String(to).length;
  const codes = [];
  for (let i = from; i <= to; i++) codes.push(`${prefix}${String(i).padStart(width, '0')}`);
  return { prefix, from, to, codes };
}

// Una celda solo se elimina si nunca se usó: sin asignaciones, sin entradas/salidas y desocupada.
// Las que tienen historial se desactivan, para no perder los reportes ni la trazabilidad.
const SIN_HISTORIAL = (sqlRef) => sqlRef`
  NOT c.ocupada
  AND NOT EXISTS (SELECT 1 FROM asignacion a WHERE a.celda_id = c.id)
  AND NOT EXISTS (SELECT 1 FROM movimiento_vehiculo m WHERE m.celda_id = c.id)`;

export default function spotRoutes(r) {
  r.get('/spots', ANY, async (ctx) => {
    const spots = await listSpots();
    if (ctx.user.role === 'residente') {
      // Los residentes solo ven la disponibilidad, no los datos de otros residentes.
      return spots.map((s) => ({
        id: s.id,
        code: s.code,
        is_disabled_spot: s.is_disabled_spot,
        is_active: s.is_active,
        is_occupied: s.is_occupied,
        state: s.state,
        mine: s.resident_id === ctx.user.resident_id,
      }));
    }
    return spots;
  });

  r.get('/spots/summary', ANY, async () => {
    const [s] = await sql`
      SELECT count(*) FILTER (WHERE activo)::int AS total,
             count(*) FILTER (WHERE activo AND ocupada)::int AS occupied,
             count(*) FILTER (WHERE activo AND NOT ocupada)::int AS free
      FROM celda`;
    return s;
  });

  r.post('/spots', ADMIN, async (ctx) => {
    required(ctx.body, ['code']);
    const [s] = await sql`
      INSERT INTO celda (codigo, para_discapacidad, observaciones)
      VALUES (${String(ctx.body.code).trim().toUpperCase()}, ${!!ctx.body.is_disabled_spot}, ${ctx.body.notes || null})
      RETURNING *`;
    await audit(null, ctx.user.id, 'crear_celda', 'celda', s.id, { code: s.code });
    spotsChanged();
    ctx.status = 201;
    return s;
  });

  // Crear varias celdas de una vez: { prefix: "D", from: 1, to: 50 } -> D01..D50
  r.post('/spots/bulk', ADMIN, async (ctx) => {
    const { prefix, from, to, codes } = rangeCodes(ctx.body);
    const rows = codes.map((code) => ({ code }));
    const created = await sql`
      INSERT INTO celda ${sql(rows)} ON CONFLICT (codigo) DO NOTHING RETURNING id`;
    await audit(null, ctx.user.id, 'crear_celdas', 'celda', null, { prefix, from, to, creadas: created.length });
    spotsChanged();
    ctx.status = 201;
    return { created: created.length };
  });

  // Eliminar varias celdas de un rango (solo las que nunca se han usado)
  r.post('/spots/bulk-delete', ADMIN, async (ctx) => {
    const { prefix, from, to, codes } = rangeCodes(ctx.body);
    const deleted = await sql`
      DELETE FROM celda c WHERE c.codigo IN ${sql(codes)} AND ${SIN_HISTORIAL(sql)}
      RETURNING c.codigo`;
    const [{ kept }] = await sql`SELECT count(*)::int AS kept FROM celda WHERE codigo IN ${sql(codes)}`;
    await audit(null, ctx.user.id, 'eliminar_celdas', 'celda', null, { prefix, from, to, eliminadas: deleted.length });
    if (deleted.length) spotsChanged();
    return { deleted: deleted.length, kept };
  });

  // Eliminar una celda (solo si nunca se ha usado; si tiene historial se debe desactivar)
  r.delete('/spots/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [s] = await sql`SELECT * FROM celda WHERE id = ${id}`;
    if (!s) throw notFound('Celda no encontrada');
    const [row] = await sql`DELETE FROM celda c WHERE c.id = ${id} AND ${SIN_HISTORIAL(sql)} RETURNING c.id`;
    if (!row) {
      throw conflict(
        `La celda ${s.code} no se puede eliminar porque está ocupada o tiene asignaciones o entradas registradas. ` +
          'Desactívela para que no se use más.',
      );
    }
    await audit(null, ctx.user.id, 'eliminar_celda', 'celda', id, { code: s.code });
    spotsChanged();
    return { ok: true };
  });

  r.patch('/spots/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const b = ctx.body;
    const [s] = await sql`
      UPDATE celda SET
        codigo = COALESCE(${b.code ? String(b.code).trim().toUpperCase() : null}, codigo),
        para_discapacidad = COALESCE(${b.is_disabled_spot ?? null}, para_discapacidad),
        activo = COALESCE(${b.is_active ?? null}, activo),
        ocupada = COALESCE(${b.is_occupied ?? null}, ocupada),
        observaciones = COALESCE(${b.notes ?? null}, observaciones)
      WHERE id = ${id} RETURNING *`;
    if (!s) throw notFound('Celda no encontrada');
    await audit(null, ctx.user.id, 'editar_celda', 'celda', id, b);
    spotsChanged();
    return s;
  });
}
