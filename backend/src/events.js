// Auditoría (RF15) y notificaciones automáticas (RF13).
import { sql } from './db.js';
import { broadcast } from './ws.js';
import { queueNotificationEmails } from './services/email.js';

export async function audit(tx, userId, action, entityName = null, entityId = null, details = null) {
  await (tx || sql)`
    INSERT INTO auditoria (cuenta_usuario_id, accion, entidad, entidad_id, detalles)
    VALUES (${userId ?? null}, ${action}, ${entityName}, ${entityId}, ${details ? sql.json(details) : null})`;
}

/**
 * Crea notificaciones para usuarios concretos o para todos los usuarios de un rol.
 * @param {{userIds?: number[], role?: string, residentIds?: number[], title: string, body?: string, kind?: string}} n
 */
export async function notify(n, tx) {
  const db = tx || sql;
  let ids = n.userIds ? [...n.userIds] : [];
  if (n.role) {
    const rows = await db`SELECT id FROM cuenta_usuario WHERE rol = ${n.role} AND activo`;
    ids.push(...rows.map((r) => r.id));
  }
  if (n.residentIds && n.residentIds.length) {
    const rows = await db`SELECT id FROM cuenta_usuario WHERE residente_id IN ${db(n.residentIds)} AND activo`;
    ids.push(...rows.map((r) => r.id));
  }
  ids = [...new Set(ids)];
  if (!ids.length) return 0;
  const rows = ids.map((id) => ({
    user_account_id: id,
    target_role: n.role || null,
    title: n.title,
    body: n.body || '',
    kind: n.kind || 'info',
  }));
  const created = await db`INSERT INTO notificacion ${db(rows)} RETURNING id`;
  // Copia por correo electrónico a residentes con correo y a la administración (si está configurado)
  queueNotificationEmails(created.map((r) => r.id));
  broadcast('notification', { title: n.title, body: n.body || '', kind: n.kind || 'info' }, { userIds: ids });
  return ids.length;
}
