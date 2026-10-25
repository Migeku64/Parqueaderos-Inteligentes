// Gestión de usuarios y roles (RF07, UC-01), bloqueo (RF18), restablecer clave (RF12).
import { sql } from '../db.js';
import { badRequest, notFound, required, intParam } from '../http.js';
import { ADMIN, hashPassword, validatePassword, randomPassword } from '../auth.js';
import { audit } from '../events.js';

const ROLES = ['admin', 'guarda', 'residente'];
const cols = sql`u.id, u.username, u.full_name, u.role, u.resident_id, u.is_active, u.is_blocked,
                 u.failed_attempts, u.must_change_password, u.last_login_at, u.created_at`;

export default function userRoutes(r) {
  r.get('/users', ADMIN, async () => {
    return sql`SELECT ${cols}, r.full_name AS resident_name
               FROM user_account u LEFT JOIN resident r ON r.id = u.resident_id
               ORDER BY u.role, u.username`;
  });

  r.post('/users', ADMIN, async (ctx) => {
    const b = ctx.body;
    required(b, ['username', 'password', 'role']);
    if (!ROLES.includes(b.role)) throw badRequest('Rol inválido');
    validatePassword(b.password);
    if (b.role === 'residente' && !b.resident_id) throw badRequest('Un usuario residente debe estar asociado a un residente');
    let fullName = b.full_name || '';
    if (b.resident_id) {
      const [res] = await sql`SELECT full_name FROM resident WHERE id = ${b.resident_id}`;
      if (!res) throw badRequest('Residente no encontrado');
      fullName = fullName || res.full_name;
    }
    const [u] = await sql`
      INSERT INTO user_account (username, full_name, password_hash, role, resident_id, must_change_password)
      VALUES (${String(b.username).trim().toLowerCase()}, ${fullName}, ${await hashPassword(b.password)},
              ${b.role}, ${b.resident_id || null}, ${b.must_change_password !== false})
      RETURNING id, username, full_name, role, resident_id, is_active, is_blocked`;
    await audit(null, ctx.user.id, 'crear_usuario', 'user_account', u.id, { username: u.username, role: u.role });
    ctx.status = 201;
    return u;
  });

  r.patch('/users/:id', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const b = ctx.body;
    if (b.role !== undefined && !ROLES.includes(b.role)) throw badRequest('Rol inválido');
    if (id === ctx.user.id && (b.is_active === false || (b.role && b.role !== 'admin'))) {
      throw badRequest('No puede desactivarse ni quitarse el rol de administrador a sí mismo');
    }
    const [u] = await sql`
      UPDATE user_account SET
        full_name = COALESCE(${b.full_name ?? null}, full_name),
        role = COALESCE(${b.role ?? null}, role),
        is_active = COALESCE(${b.is_active ?? null}, is_active)
      WHERE id = ${id}
      RETURNING id, username, full_name, role, resident_id, is_active, is_blocked`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'editar_usuario', 'user_account', id, b);
    return u;
  });

  r.post('/users/:id/block', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    if (id === ctx.user.id) throw badRequest('No puede bloquearse a sí mismo');
    const [u] = await sql`UPDATE user_account SET is_blocked = TRUE WHERE id = ${id} RETURNING id, username, is_blocked`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'usuario_bloqueado', 'user_account', id, { motivo: ctx.body.reason || 'manual' });
    return u;
  });

  r.post('/users/:id/unblock', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [u] = await sql`UPDATE user_account SET is_blocked = FALSE, failed_attempts = 0 WHERE id = ${id}
                          RETURNING id, username, is_blocked`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'usuario_desbloqueado', 'user_account', id);
    return u;
  });

  r.post('/users/:id/reset-password', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const temp = ctx.body.password || randomPassword();
    validatePassword(temp);
    const [u] = await sql`
      UPDATE user_account SET password_hash = ${await hashPassword(temp)}, must_change_password = TRUE,
             failed_attempts = 0, is_blocked = FALSE
      WHERE id = ${id} RETURNING id, username`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'restablecer_contrasena', 'user_account', id);
    return { ...u, temporary_password: temp };
  });
}
