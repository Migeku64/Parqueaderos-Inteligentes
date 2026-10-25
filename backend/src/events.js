// Auditoría (RF15) y notificaciones automáticas (RF13).
import { sql } from './db.js';
import { broadcast } from './ws.js';

export async function audit(tx, userId, action, entityName = null, entityId = null, details = null) {
  await (tx || sql)`
    INSERT INTO audit_log (user_account_id, action, entity_name, entity_id, details)
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
    const rows = await db`SELECT id FROM user_account WHERE role = ${n.role} AND is_active`;
    ids.push(...rows.map((r) => r.id));
  }
  if (n.residentIds && n.residentIds.length) {
    const rows = await db`SELECT id FROM user_account WHERE resident_id IN ${db(n.residentIds)} AND is_active`;
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
  await db`INSERT INTO notification ${db(rows)}`;
  broadcast('notification', { title: n.title, body: n.body || '', kind: n.kind || 'info' }, { userIds: ids });
  return ids.length;
}
