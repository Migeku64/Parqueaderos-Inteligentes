// Alertas automáticas de actividad sospechosa (complementan la auditoría del RF15).
// Cada alerta se notifica a la administración (en la aplicación y por correo) y queda en la auditoría.
import { sql } from '../db.js';
import { config } from '../config.js';
import { audit, notify } from '../events.js';

/** Hora local (0-23) en la zona horaria del conjunto. */
export function localHour(date = new Date()) {
  const h = new Intl.DateTimeFormat('en-US', { timeZone: config.timezone, hour: 'numeric', hourCycle: 'h23' }).format(date);
  return Number(h) % 24;
}

/** ¿La hora está dentro del horario nocturno configurado (por defecto de 10:00 p. m. a 5:00 a. m.)? */
export function isNightHour(date = new Date()) {
  const h = localHour(date);
  const { nightStart, nightEnd } = config.alerts;
  return nightStart > nightEnd ? h >= nightStart || h < nightEnd : h >= nightStart && h < nightEnd;
}

async function raise({ userId = null, type, title, body, entity = null, entityId = null, details = {} }) {
  await notify({ role: 'admin', title: `Alerta de seguridad: ${title}`, body, kind: 'alerta' });
  await audit(null, userId, 'alerta_seguridad', entity, entityId, { tipo: type, ...details });
}

/** Varios ingresos rechazados de la misma placa en poco tiempo (posible intento de ingreso indebido). */
export async function checkRejectedPlate(plate) {
  const { rejectedCount, rejectedMinutes } = config.alerts;
  const [{ n }] = await sql`
    SELECT count(*)::int AS n FROM movimiento_vehiculo
    WHERE placa = ${plate} AND NOT autorizado
      AND registrado_en >= now() - make_interval(mins => ${rejectedMinutes})`;
  // Se avisa una sola vez, justo cuando se alcanza el límite
  if (n !== rejectedCount) return false;
  await raise({
    type: 'ingresos_rechazados',
    title: `ingresos rechazados de la placa ${plate}`,
    body: `La placa ${plate} tuvo ${n} intentos de ingreso rechazados en los últimos ${rejectedMinutes} minutos. Verifique con el guarda de seguridad.`,
    entity: 'movimiento_vehiculo',
    details: { placa: plate, rechazos: n, minutos: rejectedMinutes },
  });
  return true;
}

/** Varias eliminaciones seguidas hechas por el mismo usuario. */
export async function checkMassDeletion(userId) {
  if (!userId) return false;
  const { deletionCount, deletionMinutes } = config.alerts;
  const [{ n }] = await sql`
    SELECT count(*)::int AS n FROM auditoria
    WHERE cuenta_usuario_id = ${userId} AND accion LIKE 'eliminar%'
      AND realizado_en >= now() - make_interval(mins => ${deletionMinutes})`;
  if (n !== deletionCount) return false;
  const [u] = await sql`SELECT usuario FROM cuenta_usuario WHERE id = ${userId}`;
  await raise({
    userId,
    type: 'eliminaciones_seguidas',
    title: `${n} eliminaciones seguidas`,
    body: `El usuario ${u?.username ?? userId} eliminó ${n} registros en menos de ${deletionMinutes} minutos. Revise la auditoría.`,
    entity: 'cuenta_usuario',
    entityId: userId,
    details: { eliminaciones: n, minutos: deletionMinutes },
  });
  return true;
}

/** Inicio de sesión de un administrador en horario nocturno. */
export async function checkNightAdminLogin(user, date = new Date()) {
  if (user.role !== 'admin' || !isNightHour(date)) return false;
  await raise({
    userId: user.id,
    type: 'ingreso_nocturno',
    title: `ingreso de ${user.username} en horario nocturno`,
    body: `El administrador ${user.username} inició sesión a las ${String(localHour(date)).padStart(2, '0')}:00 (hora de Colombia). Si no fue usted, cambie la contraseña y bloquee la cuenta.`,
    entity: 'cuenta_usuario',
    entityId: user.id,
    details: { usuario: user.username },
  });
  return true;
}

/** Ejecuta una verificación sin interrumpir la operación principal si algo falla. */
export function runCheck(promise) {
  return promise.catch((err) => console.error('[alertas]', err.message));
}
