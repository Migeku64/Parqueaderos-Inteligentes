// Celdas del parqueadero (UC-03), disponibilidad en tiempo real (RF04, RF09, RF16).
import { sql } from '../db.js';
import { badRequest, notFound, required, intParam } from '../http.js';
import { ADMIN, ANY } from '../auth.js';
import { audit } from '../events.js';
import { broadcast } from '../ws.js';

export async function listSpots(db = sql) {
  return db`
    SELECT s.id, s.code, s.is_disabled_spot, s.is_active, s.is_occupied, s.notes,
           a.id AS assignment_id, a.resident_id, r.full_name AS resident_name,
           CASE WHEN h.block = '' THEN h.number ELSE h.block || '-' || h.number END AS house,
           v.plate,
           CASE WHEN NOT s.is_active THEN 'inactiva'
                WHEN s.is_occupied THEN 'ocupada'
                WHEN a.id IS NOT NULL THEN 'asignada'
                ELSE 'libre' END AS state
    FROM parking_spot s
    LEFT JOIN LATERAL (
      SELECT pa.* FROM parking_assignment pa JOIN cycle c ON c.id = pa.cycle_id
      WHERE pa.parking_spot_id = s.id AND pa.status = 'vigente' AND c.status = 'activo' LIMIT 1
    ) a ON TRUE
    LEFT JOIN resident r ON r.id = a.resident_id
    LEFT JOIN house h ON h.id = r.house_id
    LEFT JOIN vehicle v ON v.id = a.vehicle_id
    ORDER BY length(s.code), s.code`;
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
      SELECT count(*) FILTER (WHERE is_active)::int AS total,
             count(*) FILTER (WHERE is_active AND is_occupied)::int AS occupied,
             count(*) FILTER (WHERE is_active AND NOT is_occupied)::int AS free
      FROM parking_spot`;
    return s;
  });

  r.post('/spots', ADMIN, async (ctx) => {
    required(ctx.body, ['code']);
    const [s] = await sql`
      INSERT INTO parking_spot (code, is_disabled_spot, notes)
      VALUES (${String(ctx.body.code).trim().toUpperCase()}, ${!!ctx.body.is_disabled_spot}, ${ctx.body.notes || null})
      RETURNING *`;
    await audit(null, ctx.user.id, 'crear_celda', 'parking_spot', s.id, { code: s.code });
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
      INSERT INTO parking_spot ${sql(rows)} ON CONFLICT (code) DO NOTHING RETURNING id`;
    await audit(null, ctx.user.id, 'crear_celdas', 'parking_spot', null, { prefix, from, to, creadas: created.length });
    spotsChanged();
    ctx.status = 201;
    return { created: created.length };
  });

  r.patch('/spots/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const b = ctx.body;
    const [s] = await sql`
      UPDATE parking_spot SET
        code = COALESCE(${b.code ? String(b.code).trim().toUpperCase() : null}, code),
        is_disabled_spot = COALESCE(${b.is_disabled_spot ?? null}, is_disabled_spot),
        is_active = COALESCE(${b.is_active ?? null}, is_active),
        is_occupied = COALESCE(${b.is_occupied ?? null}, is_occupied),
        notes = COALESCE(${b.notes ?? null}, notes)
      WHERE id = ${id} RETURNING *`;
    if (!s) throw notFound('Celda no encontrada');
    await audit(null, ctx.user.id, 'editar_celda', 'parking_spot', id, b);
    spotsChanged();
    return s;
  });
}
