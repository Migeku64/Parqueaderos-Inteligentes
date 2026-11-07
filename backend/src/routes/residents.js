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
    INSERT INTO vivienda (bloque, numero) VALUES (${b}, ${String(num)})
    ON CONFLICT (bloque, numero) DO UPDATE SET numero = EXCLUDED.numero
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
  SELECT r.*, h.bloque, h.numero AS house_number,
         CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house,
         COALESCE((SELECT json_agg(json_build_object('id', v.id, 'resident_id', v.residente_id, 'plate', v.placa, 'type', v.tipo,
                    'brand', v.marca, 'model', v.modelo, 'color', v.color, 'is_active', v.activo, 'created_at', v.creado_en)
                  ORDER BY v.id) FROM vehiculo v WHERE v.residente_id = r.id AND v.activo), '[]') AS vehicles,
         (SELECT json_build_object('id', pa.id, 'spot_code', s.codigo, 'cycle_id', c.id, 'cycle_name', c.nombre,
                                   'start_date', c.fecha_inicio, 'end_date', c.fecha_fin)
            FROM asignacion pa
            JOIN celda s ON s.id = pa.celda_id
            JOIN ciclo c ON c.id = pa.ciclo_id
           WHERE pa.residente_id = r.id AND pa.estado = 'vigente' AND c.estado = 'activo'
           LIMIT 1) AS current_assignment,
         (SELECT json_build_object('id', ua.id, 'username', ua.usuario, 'is_blocked', ua.bloqueado)
            FROM cuenta_usuario ua WHERE ua.residente_id = r.id) AS account
  FROM residente r JOIN vivienda h ON h.id = r.vivienda_id`;

export async function getResident(id, db = sql) {
  const [r] = await db`${residentSelect} WHERE r.id = ${id}`;
  return r;
}

export default function residentRoutes(r) {
  r.get('/houses', STAFF, async () => sql`SELECT * FROM vivienda ORDER BY bloque, length(numero), numero`);

  r.get('/residents', STAFF, async (ctx) => {
    const q = String(ctx.query.q || '').trim();
    const status = ctx.query.status;
    const like = `%${q}%`;
    const plate = `%${normalizePlate(q)}%`;
    return sql`
      ${residentSelect}
      WHERE (${q} = '' OR r.nombre_completo ILIKE ${like} OR r.numero_documento ILIKE ${like}
             OR h.numero ILIKE ${like} OR (h.bloque || '-' || h.numero) ILIKE ${like}
             OR EXISTS (SELECT 1 FROM vehiculo v WHERE v.residente_id = r.id AND v.placa LIKE ${plate}))
        AND (${status || null}::text IS NULL OR r.estado = ${status || null})
      ORDER BY h.bloque, length(h.numero), h.numero, r.nombre_completo
      LIMIT 500`;
  });

  r.get('/residents/:id', STAFF, async (ctx) => {
    const id = intParam(ctx.params.id);
    const res = await getResident(id);
    if (!res) throw notFound('Residente no encontrado');
    const history = await sql`
      SELECT pa.id, pa.estado, pa.metodo, pa.puntaje_ipa, pa.asignado_en, pa.liberado_en,
             c.nombre AS cycle_name, c.fecha_inicio, c.fecha_fin, s.codigo AS spot_code, v.placa
      FROM asignacion pa
      JOIN ciclo c ON c.id = pa.ciclo_id
      JOIN celda s ON s.id = pa.celda_id
      JOIN vehiculo v ON v.id = pa.vehiculo_id
      WHERE pa.residente_id = ${id}
      ORDER BY c.fecha_inicio DESC`;
    return { ...res, history };
  });

  r.post('/residents', ADMIN, async (ctx) => {
    const b = ctx.body;
    required(b, ['full_name', 'document_number', 'house_number']);
    const id = await sql.begin(async (tx) => {
      const houseId = await findOrCreateHouse(tx, b.house_block, b.house_number);
      const [res] = await tx`
        INSERT INTO residente (vivienda_id, nombre_completo, tipo_documento, numero_documento, telefono, correo,
                              deuda, puntaje_administrativo, tiene_discapacidad)
        VALUES (${houseId}, ${String(b.full_name).trim()}, ${b.document_type || 'CC'},
                ${String(b.document_number).trim()}, ${b.phone || null}, ${b.email || null},
                ${Number(b.debt) || 0}, ${Number(b.admin_score) || 0}, ${!!b.has_disability})
        RETURNING id`;
      if (b.vehicle && b.vehicle.plate) {
        const v = vehicleInput(b.vehicle);
        await tx`INSERT INTO vehiculo ${tx({ ...v, resident_id: res.id })}`;
      }
      if (b.account && b.account.username) {
        validatePassword(b.account.password);
        await tx`
          INSERT INTO cuenta_usuario (usuario, nombre_completo, hash_contrasena, rol, residente_id, debe_cambiar_contrasena)
          VALUES (${String(b.account.username).trim().toLowerCase()}, ${String(b.full_name).trim()},
                  ${await hashPassword(b.account.password)}, 'residente', ${res.id}, TRUE)`;
      }
      await audit(tx, ctx.user.id, 'crear_residente', 'residente', res.id, { nombre: b.full_name });
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
        UPDATE residente SET
          vivienda_id = ${houseId},
          nombre_completo = ${b.full_name ?? current.full_name},
          tipo_documento = ${b.document_type ?? current.document_type},
          numero_documento = ${b.document_number ?? current.document_number},
          telefono = ${b.phone !== undefined ? b.phone : current.phone},
          correo = ${b.email !== undefined ? b.email : current.email},
          estado = ${b.status ?? current.status},
          deuda = ${b.debt !== undefined ? Number(b.debt) || 0 : current.debt},
          puntaje_administrativo = ${b.admin_score !== undefined ? Number(b.admin_score) || 0 : current.admin_score},
          tiene_discapacidad = ${b.has_disability !== undefined ? !!b.has_disability : current.has_disability},
          actualizado_en = now()
        WHERE id = ${id}`;
      await audit(tx, ctx.user.id, 'editar_residente', 'residente', id, b);
    });
    return getResident(id);
  });

  // Eliminación lógica: el residente queda inactivo y se conserva su historial.
  r.delete('/residents/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [res] = await sql`UPDATE residente SET estado = 'inactivo', actualizado_en = now() WHERE id = ${id} RETURNING id`;
    if (!res) throw notFound('Residente no encontrado');
    await sql`UPDATE cuenta_usuario SET activo = FALSE WHERE residente_id = ${id}`;
    await audit(null, ctx.user.id, 'inactivar_residente', 'residente', id);
    return { ok: true };
  });

  // ---------------- Vehículos ----------------
  r.get('/vehicles', STAFF, async (ctx) => {
    const plate = normalizePlate(ctx.query.plate);
    return sql`
      SELECT v.*, r.nombre_completo AS resident_name,
             CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house
      FROM vehiculo v JOIN residente r ON r.id = v.residente_id JOIN vivienda h ON h.id = r.vivienda_id
      WHERE (${plate} = '' OR v.placa LIKE ${'%' + plate + '%'})
      ORDER BY v.placa LIMIT 500`;
  });

  r.post('/residents/:id/vehicles', ADMIN, async (ctx) => {
    const residentId = intParam(ctx.params.id);
    required(ctx.body, ['plate']);
    const v = vehicleInput(ctx.body);
    const [row] = await sql`INSERT INTO vehiculo ${sql({ ...v, resident_id: residentId })} RETURNING *`;
    await audit(null, ctx.user.id, 'crear_vehiculo', 'vehiculo', row.id, { placa: v.plate });
    ctx.status = 201;
    return row;
  });

  r.put('/vehicles/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [cur] = await sql`SELECT * FROM vehiculo WHERE id = ${id}`;
    if (!cur) throw notFound('Vehículo no encontrado');
    const v = vehicleInput({ ...cur, ...ctx.body });
    const [row] = await sql`
      UPDATE vehiculo SET placa = ${v.plate}, tipo = ${v.type}, marca = ${v.brand}, modelo = ${v.model},
             color = ${v.color}, activo = ${ctx.body.is_active ?? cur.is_active}
      WHERE id = ${id} RETURNING *`;
    await audit(null, ctx.user.id, 'editar_vehiculo', 'vehiculo', id, ctx.body);
    return row;
  });

  r.delete('/vehicles/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [row] = await sql`UPDATE vehiculo SET activo = FALSE WHERE id = ${id} RETURNING id, placa`;
    if (!row) throw notFound('Vehículo no encontrado');
    await audit(null, ctx.user.id, 'inactivar_vehiculo', 'vehiculo', id, { placa: row.plate });
    return { ok: true };
  });
}
