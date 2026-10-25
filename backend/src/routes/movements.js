// Entradas y salidas de vehículos (RF05, RF06, UC-05) y lectura automática de placas.
import { sql } from '../db.js';
import { HttpError, badRequest, required, normalizePlate } from '../http.js';
import { config } from '../config.js';
import { STAFF } from '../auth.js';
import { audit, notify } from '../events.js';
import { broadcast } from '../ws.js';
import { spotsChanged } from './spots.js';

/** Busca el vehículo, su residente y la asignación vigente del ciclo activo. */
export async function lookupPlate(plate, db = sql) {
  const [v] = await db`
    SELECT v.id AS vehicle_id, v.plate, v.type, v.brand, v.model, v.color, v.is_active,
           r.id AS resident_id, r.full_name, r.status AS resident_status,
           CASE WHEN h.block = '' THEN h.number ELSE h.block || '-' || h.number END AS house
    FROM vehicle v JOIN resident r ON r.id = v.resident_id JOIN house h ON h.id = r.house_id
    WHERE v.plate = ${plate}`;
  if (!v) return { plate, vehicle: null, assignment: null, inside: false };
  const [a] = await db`
    SELECT pa.id, pa.parking_spot_id, s.code AS spot_code, s.is_occupied, c.name AS cycle_name, c.end_date
    FROM parking_assignment pa
    JOIN cycle c ON c.id = pa.cycle_id JOIN parking_spot s ON s.id = pa.parking_spot_id
    WHERE pa.resident_id = ${v.resident_id} AND pa.status = 'vigente' AND c.status = 'activo'
    LIMIT 1`;
  const [last] = await db`
    SELECT type FROM vehicle_movement WHERE plate = ${plate} AND authorized ORDER BY recorded_at DESC, id DESC LIMIT 1`;
  return { plate, vehicle: v, assignment: a || null, inside: last?.type === 'entrada' };
}

async function registerMovement({ plate: rawPlate, type, userId, source = 'manual' }) {
  const plate = normalizePlate(rawPlate);
  if (!/^[A-Z0-9]{5,7}$/.test(plate)) throw badRequest('Placa inválida');
  if (!['entrada', 'salida'].includes(type)) throw badRequest('Tipo de movimiento inválido (entrada | salida)');

  const result = await sql.begin(async (tx) => {
    await tx`SELECT pg_advisory_xact_lock(7777, hashtext(${plate}))`;
    const info = await lookupPlate(plate, tx);
    let authorized = true;
    let reason = null;
    let spotId = null;

    if (type === 'entrada') {
      if (!info.vehicle) {
        authorized = false;
        reason = 'Vehículo no registrado en el conjunto';
      } else if (!info.vehicle.is_active || info.vehicle.resident_status !== 'activo') {
        authorized = false;
        reason = 'Vehículo o residente inactivo';
      } else if (!info.assignment) {
        authorized = false;
        reason = 'El residente no tiene parqueadero asignado en el ciclo actual';
      } else if (info.inside) {
        throw new HttpError(409, `El vehículo ${plate} ya tiene una entrada registrada (celda ${info.assignment.spot_code})`);
      } else {
        spotId = info.assignment.parking_spot_id;
        await tx`UPDATE parking_spot SET is_occupied = TRUE WHERE id = ${spotId}`;
      }
    } else {
      if (!info.inside) reason = 'Salida sin entrada registrada';
      // Libera la celda en la que estaba (la de su asignación o la de su última entrada)
      const [lastIn] = await tx`
        SELECT parking_spot_id FROM vehicle_movement
        WHERE plate = ${plate} AND type = 'entrada' AND authorized ORDER BY recorded_at DESC, id DESC LIMIT 1`;
      spotId = info.assignment?.parking_spot_id ?? lastIn?.parking_spot_id ?? null;
      if (spotId && info.inside) await tx`UPDATE parking_spot SET is_occupied = FALSE WHERE id = ${spotId}`;
    }

    const [m] = await tx`
      INSERT INTO vehicle_movement (plate, vehicle_id, parking_spot_id, assignment_id, type, authorized, source, reason, recorded_by)
      VALUES (${plate}, ${info.vehicle?.vehicle_id ?? null}, ${spotId}, ${info.assignment?.id ?? null},
              ${type}, ${authorized}, ${source}, ${reason}, ${userId ?? null})
      RETURNING *`;
    await audit(tx, userId, authorized ? `registro_${type}` : 'ingreso_rechazado', 'vehicle_movement', m.id, { placa: plate, motivo: reason });
    if (!authorized) {
      await notify(
        {
          role: 'admin',
          title: `Ingreso no autorizado: ${plate}`,
          body: `${reason}${info.vehicle ? ` (${info.vehicle.full_name}, casa ${info.vehicle.house})` : ''}.`,
          kind: 'alerta',
        },
        tx,
      );
    }
    return {
      movement: m,
      authorized,
      reason,
      spot_code: info.assignment?.spot_code ?? null,
      resident: info.vehicle ? { id: info.vehicle.resident_id, full_name: info.vehicle.full_name, house: info.vehicle.house } : null,
      message: authorized
        ? type === 'entrada'
          ? `Entrada autorizada. Diríjase a la celda ${info.assignment.spot_code}.`
          : `Salida registrada${reason ? ` (${reason.toLowerCase()})` : ''}.`
        : `Ingreso NO autorizado: ${reason}.`,
    };
  });
  broadcast('movement', { plate, type, authorized: result.authorized, spot_code: result.spot_code });
  spotsChanged();
  return result;
}

export default function movementRoutes(r) {
  // Consulta rápida de una placa (sin registrar nada)
  r.get('/movements/check/:plate', STAFF, async (ctx) => {
    const plate = normalizePlate(ctx.params.plate);
    const info = await lookupPlate(plate);
    return { ...info, can_enter: !!(info.vehicle && info.assignment && !info.inside) };
  });

  r.post('/movements', STAFF, async (ctx) => {
    required(ctx.body, ['plate', 'type']);
    const res = await registerMovement({ plate: ctx.body.plate, type: ctx.body.type, userId: ctx.user.id });
    ctx.status = 201;
    return res;
  });

  // Integración con cámaras lectoras de placas (ANPR): header X-Device-Key = PLATE_READER_KEY
  r.post('/movements/reader', async (ctx) => {
    if (!config.plateReaderKey || ctx.req.headers['x-device-key'] !== config.plateReaderKey) {
      throw new HttpError(401, 'Dispositivo no autorizado');
    }
    required(ctx.body, ['plate', 'type']);
    const res = await registerMovement({ plate: ctx.body.plate, type: ctx.body.type, source: 'lector' });
    ctx.status = 201;
    return res;
  });

  r.get('/movements', STAFF, async (ctx) => {
    const q = ctx.query;
    const plate = normalizePlate(q.plate);
    const limit = Math.min(Number(q.limit) || 200, 2000);
    return sql`
      SELECT m.*, s.code AS spot_code, ua.username AS recorded_by_username,
             r.full_name AS resident_name
      FROM vehicle_movement m
      LEFT JOIN parking_spot s ON s.id = m.parking_spot_id
      LEFT JOIN user_account ua ON ua.id = m.recorded_by
      LEFT JOIN vehicle v ON v.id = m.vehicle_id
      LEFT JOIN resident r ON r.id = v.resident_id
      WHERE (${plate} = '' OR m.plate LIKE ${'%' + plate + '%'})
        AND (${q.from || null}::date IS NULL OR m.recorded_at >= ${q.from || null}::date)
        AND (${q.to || null}::date IS NULL OR m.recorded_at < ${q.to || null}::date + 1)
        AND (${q.authorized ?? null}::boolean IS NULL OR m.authorized = ${q.authorized ?? null}::boolean)
      ORDER BY m.recorded_at DESC, m.id DESC
      LIMIT ${limit}`;
  });
}
