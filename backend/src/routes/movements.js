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
    SELECT v.id AS vehiculo_id, v.placa, v.tipo, v.marca, v.modelo, v.color, v.activo,
           r.id AS residente_id, r.nombre_completo, r.estado AS resident_status,
           CASE WHEN h.bloque = '' THEN h.numero ELSE h.bloque || '-' || h.numero END AS house
    FROM vehiculo v JOIN residente r ON r.id = v.residente_id JOIN vivienda h ON h.id = r.vivienda_id
    WHERE v.placa = ${plate}`;
  if (!v) return { plate, vehicle: null, assignment: null, inside: false };
  const [a] = await db`
    SELECT pa.id, pa.celda_id, s.codigo AS spot_code, s.ocupada, c.nombre AS cycle_name, c.fecha_fin
    FROM asignacion pa
    JOIN ciclo c ON c.id = pa.ciclo_id JOIN celda s ON s.id = pa.celda_id
    WHERE pa.residente_id = ${v.resident_id} AND pa.estado = 'vigente' AND c.estado = 'activo'
    LIMIT 1`;
  const [last] = await db`
    SELECT tipo FROM movimiento_vehiculo WHERE placa = ${plate} AND autorizado ORDER BY registrado_en DESC, id DESC LIMIT 1`;
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
        await tx`UPDATE celda SET ocupada = TRUE WHERE id = ${spotId}`;
      }
    } else {
      if (!info.inside) reason = 'Salida sin entrada registrada';
      // Libera la celda en la que estaba (la de su asignación o la de su última entrada)
      const [lastIn] = await tx`
        SELECT celda_id FROM movimiento_vehiculo
        WHERE placa = ${plate} AND tipo = 'entrada' AND autorizado ORDER BY registrado_en DESC, id DESC LIMIT 1`;
      spotId = info.assignment?.parking_spot_id ?? lastIn?.parking_spot_id ?? null;
      if (spotId && info.inside) await tx`UPDATE celda SET ocupada = FALSE WHERE id = ${spotId}`;
    }

    const [m] = await tx`
      INSERT INTO movimiento_vehiculo (placa, vehiculo_id, celda_id, asignacion_id, tipo, autorizado, origen, motivo, registrado_por)
      VALUES (${plate}, ${info.vehicle?.vehicle_id ?? null}, ${spotId}, ${info.assignment?.id ?? null},
              ${type}, ${authorized}, ${source}, ${reason}, ${userId ?? null})
      RETURNING *`;
    await audit(tx, userId, authorized ? `registro_${type}` : 'ingreso_rechazado', 'movimiento_vehiculo', m.id, { placa: plate, motivo: reason });
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
      SELECT m.*, s.codigo AS spot_code, ua.usuario AS recorded_by_username,
             r.nombre_completo AS resident_name
      FROM movimiento_vehiculo m
      LEFT JOIN celda s ON s.id = m.celda_id
      LEFT JOIN cuenta_usuario ua ON ua.id = m.registrado_por
      LEFT JOIN vehiculo v ON v.id = m.vehiculo_id
      LEFT JOIN residente r ON r.id = v.residente_id
      WHERE (${plate} = '' OR m.placa LIKE ${'%' + plate + '%'})
        AND (${q.from || null}::date IS NULL OR m.registrado_en >= ${q.from || null}::date)
        AND (${q.to || null}::date IS NULL OR m.registrado_en < ${q.to || null}::date + 1)
        AND (${q.authorized ?? null}::boolean IS NULL OR m.autorizado = ${q.authorized ?? null}::boolean)
      ORDER BY m.registrado_en DESC, m.id DESC
      LIMIT ${limit}`;
  });
}
