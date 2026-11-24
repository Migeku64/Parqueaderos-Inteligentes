// Informe automático de auditoría: resumen de la actividad de los últimos días,
// enviado a la administración (en la aplicación y por correo) una vez por semana.
import { sql } from '../db.js';
import { config } from '../config.js';
import { audit, notify } from '../events.js';
import { localHour } from './alerts.js';

const LABELS = [
  ['login', 'Inicios de sesión'],
  ['login_fallido', 'Intentos de inicio de sesión fallidos'],
  ['usuario_bloqueado', 'Cuentas bloqueadas'],
  ['alerta_seguridad', 'Alertas de seguridad'],
  ['ingreso_rechazado', 'Ingresos rechazados en portería'],
  ['registro_entrada', 'Entradas registradas'],
  ['registro_salida', 'Salidas registradas'],
  ['sorteo', 'Sorteos realizados'],
  ['sorteo_automatico', 'Sorteos automáticos'],
  ['asignacion_manual', 'Asignaciones manuales'],
  ['cancelar_asignacion', 'Asignaciones canceladas'],
];

/** Resumen de la auditoría de los últimos `days` días. */
export async function auditSummary(days = 7) {
  const since = sql`now() - make_interval(days => ${days})`;
  const byAction = await sql`
    SELECT accion, count(*)::int AS n FROM auditoria WHERE realizado_en >= ${since} GROUP BY accion`;
  const count = Object.fromEntries(byAction.map((r) => [r.action, r.n]));
  const sum = (prefix) => byAction.filter((r) => r.action.startsWith(prefix)).reduce((a, r) => a + r.n, 0);
  const [backups] = await sql`
    SELECT count(*) FILTER (WHERE estado = 'ok')::int AS ok, count(*) FILTER (WHERE estado = 'error')::int AS error
    FROM respaldo WHERE creado_en >= ${since}`;
  const topUsers = await sql`
    SELECT coalesce(u.usuario, 'sistema') AS usuario, count(*)::int AS n
    FROM auditoria a LEFT JOIN cuenta_usuario u ON u.id = a.cuenta_usuario_id
    WHERE a.realizado_en >= ${since} GROUP BY 1 ORDER BY n DESC LIMIT 5`;
  const items = LABELS.map(([key, label]) => ({ key, label, value: count[key] || 0 }));
  items.push(
    { key: 'creaciones', label: 'Registros creados', value: sum('crear_') },
    { key: 'ediciones', label: 'Registros editados', value: sum('editar_') },
    { key: 'eliminaciones', label: 'Registros eliminados', value: sum('eliminar_') },
    { key: 'inactivaciones', label: 'Registros inactivados', value: sum('inactivar_') },
    { key: 'respaldos_ok', label: 'Respaldos correctos', value: backups.ok },
    { key: 'respaldos_error', label: 'Respaldos con error', value: backups.error },
  );
  const total = byAction.reduce((a, r) => a + r.n, 0);
  return { days, total, items, top_users: topUsers.map((u) => ({ username: u.username, actions: u.n })) };
}

export function summaryText(s) {
  const lines = [`Actividad de los últimos ${s.days} días (${s.total} acciones registradas):`, ''];
  for (const it of s.items) if (it.value) lines.push(`• ${it.label}: ${it.value}`);
  if (s.top_users.length) {
    lines.push('', 'Usuarios con más acciones:');
    for (const u of s.top_users) lines.push(`• ${u.username}: ${u.actions}`);
  }
  const warn = s.items.filter((i) => ['alerta_seguridad', 'usuario_bloqueado', 'respaldos_error'].includes(i.key) && i.value);
  lines.push('', warn.length ? 'Revise las alertas en Auditoría y respaldos.' : 'No se presentaron alertas de seguridad.');
  return lines.join('\n');
}

/** Envía el informe a la administración y lo deja en la auditoría. */
export async function sendAuditReport({ userId = null, days = 7, automatic = false } = {}) {
  const s = await auditSummary(days);
  await notify({
    role: 'admin',
    title: automatic ? 'Informe semanal de auditoría' : 'Informe de auditoría',
    body: summaryText(s),
    kind: 'informe_auditoria',
  });
  await audit(null, userId, 'informe_auditoria', null, null, { dias: days, automatico: automatic, acciones: s.total });
  return s;
}

/**
 * Tarea programada: envía el informe el día configurado (lunes por defecto) desde la hora configurada,
 * una sola vez por semana. Si la API estuvo apagada ese día, lo envía en cuanto despierte.
 */
export async function runScheduledAuditReport(now = new Date()) {
  const { weekday, hour } = config.auditReport;
  if (weekday < 0) return false;
  const [last] = await sql`
    SELECT max(realizado_en) AS at FROM auditoria
    WHERE accion = 'informe_auditoria' AND (detalles->>'automatico')::boolean`;
  const lastAt = last?.at ? new Date(last.at) : null;
  const daysSince = lastAt ? (now - lastAt) / 86_400_000 : Infinity;
  const localDay = new Intl.DateTimeFormat('en-US', { timeZone: config.timezone, weekday: 'short' }).format(now);
  const isReportDay = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(localDay) === weekday;
  const due = (isReportDay && localHour(now) >= hour && daysSince > 2) || daysSince > 8;
  if (!due) return false;
  await sendAuditReport({ automatic: true });
  return true;
}
