// Residentes (RF01, UC-02) y vehículos (RF02).
import { sql } from '../db.js';
import { badRequest, notFound, required, intParam, normalizePlate } from '../http.js';
import { ADMIN, STAFF, hashPassword, validatePassword } from '../auth.js';
import { audit } from '../events.js';
import { config } from '../config.js';

const VEHICLE_TYPES = ['carro', 'moto', 'camioneta', 'otro'];

async function findOrCreateHouse(tx, block, number) {
  const b = String(block || '').trim().toUpperCase();
  const n = String(number || '').trim();
  if (!n) throw badRequest('El número de casa es obligatorio');
  const num = Number(n);
  if (!Number.isInteger(num) || num < config.houseMin || num > config.houseMax) {
    throw badRequest(`El número de casa debe estar entre ${config.houseMin} y ${config.houseMax}`);
  }
  const [h] = await tx`
    INSERT INTO house (block, number) VALUES (${b}, ${String(num)})
    ON CONFLICT (block, number) DO UPDATE SET number = EXCLUDED.number
    RETURNING id`;
  return h.id;
}

function vehicleInput(v) {
  const plate = normalizePlate(v.plate);
  if (!/^[A-Z0-9]{5,7}$/.test(plate)) throw badRequest('Placa inválida (use 5 a 7 letras o números, ej. ABC123)');
  const type = v.type || 'carro';
  if (!VEHICLE_TYPES.includes(type)) throw badRequest('Tipo de vehículo inválido');
  return { plate, type, brand: v.brand || null, model: v.model || null, color: v.color || null };
}

const residentSelect = sql`
  SELECT r.*, h.block, h.number AS house_number,
         CASE WHEN h.block = '' THEN h.number ELSE h.block || '-' || h.number END AS house,
         COALESCE((SELECT json_agg(v ORDER BY v.id) FROM vehicle v WHERE v.resident_id = r.id AND v.is_active), '[]') AS vehicles,
         (SELECT json_build_object('id', pa.id, 'spot_code', s.code, 'cycle_id', c.id, 'cycle_name', c.name,
                                   'start_date', c.start_date, 'end_date', c.end_date)
            FROM parking_assignment pa
            JOIN parking_spot s ON s.id = pa.parking_spot_id
            JOIN cycle c ON c.id = pa.cycle_id
           WHERE pa.resident_id = r.id AND pa.status = 'vigente' AND c.status = 'activo'
           LIMIT 1) AS current_assignment,
         (SELECT json_build_object('id', ua.id, 'username', ua.username, 'is_blocked', ua.is_blocked)
            FROM user_account ua WHERE ua.resident_id = r.id) AS account
  FROM resident r JOIN house h ON h.id = r.house_id`;

export async function getResident(id, db = sql) {
  const [r] = await db`${residentSelect} WHERE r.id = ${id}`;
  return r;
}

export default function residentRoutes(r) {
  r.get('/houses', STAFF, async () => sql`SELECT * FROM house ORDER BY block, length(number), number`);

  r.get('/residents', STAFF, async (ctx) => {
    const q = String(ctx.query.q || '').trim();
    const status = ctx.query.status;
    const like = `%${q}%`;
    const plate = `%${normalizePlate(q)}%`;
    return sql`
      ${residentSelect}
      WHERE (${q} = '' OR r.full_name ILIKE ${like} OR r.document_number ILIKE ${like}
             OR h.number ILIKE ${like} OR (h.block || '-' || h.number) ILIKE ${like}
             OR EXISTS (SELECT 1 FROM vehicle v WHERE v.resident_id = r.id AND v.plate LIKE ${plate}))
        AND (${status || null}::text IS NULL OR r.status = ${status || null})
      ORDER BY h.block, length(h.number), h.number, r.full_name
      LIMIT 500`;
  });

  r.get('/residents/:id', STAFF, async (ctx) => {
    const id = intParam(ctx.params.id);
    const res = await getResident(id);
    if (!res) throw notFound('Residente no encontrado');
    const history = await sql`
      SELECT pa.id, pa.status, pa.method, pa.ipa_score, pa.assigned_at, pa.released_at,
             c.name AS cycle_name, c.start_date, c.end_date, s.code AS spot_code, v.plate
      FROM parking_assignment pa
      JOIN cycle c ON c.id = pa.cycle_id
      JOIN parking_spot s ON s.id = pa.parking_spot_id
      JOIN vehicle v ON v.id = pa.vehicle_id
      WHERE pa.resident_id = ${id}
      ORDER BY c.start_date DESC`;
    return { ...res, history };
  });

  r.post('/residents', ADMIN, async (ctx) => {
    const b = ctx.body;
    required(b, ['full_name', 'document_number', 'house_number']);
    const id = await sql.begin(async (tx) => {
      const houseId = await findOrCreateHouse(tx, b.house_block, b.house_number);
      const [res] = await tx`
        INSERT INTO resident (house_id, full_name, document_type, document_number, phone, email,
                              debt, admin_score, has_disability)
        VALUES (${houseId}, ${String(b.full_name).trim()}, ${b.document_type || 'CC'},
                ${String(b.document_number).trim()}, ${b.phone || null}, ${b.email || null},
                ${Number(b.debt) || 0}, ${Number(b.admin_score) || 0}, ${!!b.has_disability})
        RETURNING id`;
      if (b.vehicle && b.vehicle.plate) {
        const v = vehicleInput(b.vehicle);
        await tx`INSERT INTO vehicle ${tx({ ...v, resident_id: res.id })}`;
      }
      if (b.account && b.account.username) {
        validatePassword(b.account.password);
        await tx`
          INSERT INTO user_account (username, full_name, password_hash, role, resident_id, must_change_password)
          VALUES (${String(b.account.username).trim().toLowerCase()}, ${String(b.full_name).trim()},
                  ${await hashPassword(b.account.password)}, 'residente', ${res.id}, TRUE)`;
      }
      await audit(tx, ctx.user.id, 'crear_residente', 'resident', res.id, { nombre: b.full_name });
      return res.id;
    });
    ctx.status = 201;
    return getResident(id);
  });

  r.put('/residents/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const b = ctx.body;
    const current = await getResident(id);
    if (!current) throw notFound('Residente no encontrado');
    await sql.begin(async (tx) => {
      let houseId = current.house_id;
      if (b.house_number !== undefined || b.house_block !== undefined) {
        houseId = await findOrCreateHouse(tx, b.house_block ?? current.block, b.house_number ?? current.house_number);
      }
      await tx`
        UPDATE resident SET
          house_id = ${houseId},
          full_name = ${b.full_name ?? current.full_name},
          document_type = ${b.document_type ?? current.document_type},
          document_number = ${b.document_number ?? current.document_number},
          phone = ${b.phone !== undefined ? b.phone : current.phone},
          email = ${b.email !== undefined ? b.email : current.email},
          status = ${b.status ?? current.status},
          debt = ${b.debt !== undefined ? Number(b.debt) || 0 : current.debt},
          admin_score = ${b.admin_score !== undefined ? Number(b.admin_score) || 0 : current.admin_score},
          has_disability = ${b.has_disability !== undefined ? !!b.has_disability : current.has_disability},
          updated_at = now()
        WHERE id = ${id}`;
      await audit(tx, ctx.user.id, 'editar_residente', 'resident', id, b);
    });
    return getResident(id);
  });

  // Eliminación lógica: el residente queda inactivo y se conserva su historial.
  r.delete('/residents/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [res] = await sql`UPDATE resident SET status = 'inactivo', updated_at = now() WHERE id = ${id} RETURNING id`;
    if (!res) throw notFound('Residente no encontrado');
    await sql`UPDATE user_account SET is_active = FALSE WHERE resident_id = ${id}`;
    await audit(null, ctx.user.id, 'inactivar_residente', 'resident', id);
    return { ok: true };
  });

  // ---------------- Vehículos ----------------
  r.get('/vehicles', STAFF, async (ctx) => {
    const plate = normalizePlate(ctx.query.plate);
    return sql`
      SELECT v.*, r.full_name AS resident_name,
             CASE WHEN h.block = '' THEN h.number ELSE h.block || '-' || h.number END AS house
      FROM vehicle v JOIN resident r ON r.id = v.resident_id JOIN house h ON h.id = r.house_id
      WHERE (${plate} = '' OR v.plate LIKE ${'%' + plate + '%'})
      ORDER BY v.plate LIMIT 500`;
  });

  r.post('/residents/:id/vehicles', ADMIN, async (ctx) => {
    const residentId = intParam(ctx.params.id);
    required(ctx.body, ['plate']);
    const v = vehicleInput(ctx.body);
    const [row] = await sql`INSERT INTO vehicle ${sql({ ...v, resident_id: residentId })} RETURNING *`;
    await audit(null, ctx.user.id, 'crear_vehiculo', 'vehicle', row.id, { placa: v.plate });
    ctx.status = 201;
    return row;
  });

  r.put('/vehicles/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [cur] = await sql`SELECT * FROM vehicle WHERE id = ${id}`;
    if (!cur) throw notFound('Vehículo no encontrado');
    const v = vehicleInput({ ...cur, ...ctx.body });
    const [row] = await sql`
      UPDATE vehicle SET plate = ${v.plate}, type = ${v.type}, brand = ${v.brand}, model = ${v.model},
             color = ${v.color}, is_active = ${ctx.body.is_active ?? cur.is_active}
      WHERE id = ${id} RETURNING *`;
    await audit(null, ctx.user.id, 'editar_vehiculo', 'vehicle', id, ctx.body);
    return row;
  });

  r.delete('/vehicles/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [row] = await sql`UPDATE vehicle SET is_active = FALSE WHERE id = ${id} RETURNING id, plate`;
    if (!row) throw notFound('Vehículo no encontrado');
    await audit(null, ctx.user.id, 'inactivar_vehiculo', 'vehicle', id, { placa: row.plate });
    return { ok: true };
  });
}
