// Gestión de usuarios y roles (RF07, UC-01), bloqueo (RF18), restablecer clave (RF12).
import { sql } from '../db.js';
import { badRequest, notFound, required, intParam } from '../http.js';
import { ADMIN, hashPassword, validatePassword, randomPassword } from '../auth.js';
import { audit } from '../events.js';

const ROLES = ['admin', 'guarda', 'residente'];
const cols = sql`u.id, u.usuario, u.nombre_completo, u.rol, u.residente_id, u.activo, u.bloqueado,
                 u.intentos_fallidos, u.debe_cambiar_contrasena, u.ultimo_ingreso_en, u.creado_en`;

export default function userRoutes(r) {
  r.get('/users', ADMIN, async () => {
    return sql`SELECT ${cols}, r.nombre_completo AS resident_name
               FROM cuenta_usuario u LEFT JOIN residente r ON r.id = u.residente_id
               ORDER BY u.rol, u.usuario`;
  });

  r.post('/users', ADMIN, async (ctx) => {
    const b = ctx.body;
    required(b, ['username', 'password', 'role']);
    if (!ROLES.includes(b.role)) throw badRequest('Rol inválido');
    validatePassword(b.password);
    if (b.role === 'residente' && !b.resident_id) throw badRequest('Un usuario residente debe estar asociado a un residente');
    let fullName = b.full_name || '';
    if (b.resident_id) {
      const [res] = await sql`SELECT nombre_completo FROM residente WHERE id = ${b.resident_id}`;
      if (!res) throw badRequest('Residente no encontrado');
      fullName = fullName || res.full_name;
    }
    const [u] = await sql`
      INSERT INTO cuenta_usuario (usuario, nombre_completo, hash_contrasena, rol, residente_id, debe_cambiar_contrasena)
      VALUES (${String(b.username).trim().toLowerCase()}, ${fullName}, ${await hashPassword(b.password)},
              ${b.role}, ${b.resident_id || null}, ${b.must_change_password !== false})
      RETURNING id, usuario, nombre_completo, rol, residente_id, activo, bloqueado`;
    await audit(null, ctx.user.id, 'crear_usuario', 'cuenta_usuario', u.id, { username: u.username, role: u.role });
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
      UPDATE cuenta_usuario SET
        nombre_completo = COALESCE(${b.full_name ?? null}, nombre_completo),
        rol = COALESCE(${b.role ?? null}, rol),
        activo = COALESCE(${b.is_active ?? null}, activo)
      WHERE id = ${id}
      RETURNING id, usuario, nombre_completo, rol, residente_id, activo, bloqueado`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'editar_usuario', 'cuenta_usuario', id, b);
    return u;
  });

  r.post('/users/:id/block', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    if (id === ctx.user.id) throw badRequest('No puede bloquearse a sí mismo');
    const [u] = await sql`UPDATE cuenta_usuario SET bloqueado = TRUE WHERE id = ${id} RETURNING id, usuario, bloqueado`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'usuario_bloqueado', 'cuenta_usuario', id, { motivo: ctx.body.reason || 'manual' });
    return u;
  });

  r.post('/users/:id/unblock', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const [u] = await sql`UPDATE cuenta_usuario SET bloqueado = FALSE, intentos_fallidos = 0 WHERE id = ${id}
                          RETURNING id, usuario, bloqueado`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'usuario_desbloqueado', 'cuenta_usuario', id);
    return u;
  });

  r.post('/users/:id/reset-password', ADMIN, async (ctx) => {
    const id = intParam(ctx.params.id);
    const temp = ctx.body.password || randomPassword();
    validatePassword(temp);
    const [u] = await sql`
      UPDATE cuenta_usuario SET hash_contrasena = ${await hashPassword(temp)}, debe_cambiar_contrasena = TRUE,
             intentos_fallidos = 0, bloqueado = FALSE
      WHERE id = ${id} RETURNING id, usuario`;
    if (!u) throw notFound('Usuario no encontrado');
    await audit(null, ctx.user.id, 'restablecer_contrasena', 'cuenta_usuario', id);
    return { ...u, temporary_password: temp };
  });
}
