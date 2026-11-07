// Celdas del parqueadero (UC-03), disponibilidad en tiempo real (RF04, RF09, RF16).
import { sql } from '../db.js';
import { badRequest, notFound, required, intParam } from '../http.js';
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
    const prefix = String(ctx.body.prefix ?? '').trim().toUpperCase();
    const from = Number(ctx.body.from);
    const to = Number(ctx.body.to);
    if (!Number.isInteger(from) || !Number.isInteger(to) || from < 1 || to < from || to - from > 500) {
      throw badRequest('Rango inválido');
    }
    const width = String(to).length < 2 ? 2 : String(to).length;
    const rows = [];
    for (let i = from; i <= to; i++) rows.push({ code: `${prefix}${String(i).padStart(width, '0')}` });
    const created = await sql`
      INSERT INTO celda ${sql(rows)} ON CONFLICT (codigo) DO NOTHING RETURNING id`;
    await audit(null, ctx.user.id, 'crear_celdas', 'celda', null, { prefix, from, to, creadas: created.length });
    spotsChanged();
    ctx.status = 201;
    return { created: created.length };
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
