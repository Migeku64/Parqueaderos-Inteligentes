// Autenticación (RF11), recuperación de credenciales (RF12), bloqueo (RF18).
import { sql } from '../db.js';
import { HttpError, required } from '../http.js';
import { config } from '../config.js';
import { ANY, signToken, verifyPassword, hashPassword, validatePassword } from '../auth.js';
import { audit, notify } from '../events.js';

const publicUser = (u) => ({
  id: u.id,
  username: u.username,
  full_name: u.full_name,
  role: u.role,
  resident_id: u.resident_id,
  must_change_password: u.must_change_password,
});

export default function authRoutes(r) {
  r.post('/auth/login', async (ctx) => {
    required(ctx.body, ['username', 'password']);
    const username = String(ctx.body.username).trim().toLowerCase();
    const [u] = await sql`SELECT * FROM user_account WHERE lower(username) = ${username}`;
    const fail = () => new HttpError(401, 'Usuario o contraseña incorrectos');
    if (!u || !u.is_active) throw fail();
    if (u.is_blocked) throw new HttpError(423, 'Usuario bloqueado. Comuníquese con la administración.');

    const ok = await verifyPassword(ctx.body.password, u.password_hash);
    if (!ok) {
      const attempts = u.failed_attempts + 1;
      const block = attempts >= config.maxFailedLogins;
      await sql`UPDATE user_account SET failed_attempts = ${attempts}, is_blocked = ${block} WHERE id = ${u.id}`;
      await audit(null, u.id, 'login_fallido', 'user_account', u.id, { attempts });
      if (block) {
        await audit(null, u.id, 'usuario_bloqueado', 'user_account', u.id, { motivo: 'intentos fallidos' });
        await notify({
          role: 'admin',
          title: 'Usuario bloqueado',
          body: `El usuario ${u.username} fue bloqueado por ${attempts} intentos fallidos de inicio de sesión.`,
          kind: 'alerta',
        });
        throw new HttpError(423, 'Usuario bloqueado por intentos fallidos. Comuníquese con la administración.');
      }
      throw fail();
    }
    await sql`UPDATE user_account SET failed_attempts = 0, last_login_at = now() WHERE id = ${u.id}`;
    await audit(null, u.id, 'login', 'user_account', u.id);
    return { token: signToken({ sub: u.id, role: u.role }), user: publicUser(u) };
  });

  r.get('/auth/me', ANY, async (ctx) => ({ user: publicUser(ctx.user) }));

  r.post('/auth/change-password', ANY, async (ctx) => {
    required(ctx.body, ['current_password', 'new_password']);
    validatePassword(ctx.body.new_password);
    const [u] = await sql`SELECT password_hash FROM user_account WHERE id = ${ctx.user.id}`;
    if (!(await verifyPassword(ctx.body.current_password, u.password_hash))) {
      throw new HttpError(400, 'La contraseña actual no es correcta');
    }
    const hash = await hashPassword(ctx.body.new_password);
    await sql`UPDATE user_account SET password_hash = ${hash}, must_change_password = FALSE WHERE id = ${ctx.user.id}`;
    await audit(null, ctx.user.id, 'cambio_contrasena', 'user_account', ctx.user.id);
    return { ok: true, message: 'Contraseña actualizada' };
  });

  // Solicitud de recuperación: notifica a la administración, que genera una clave temporal.
  r.post('/auth/forgot', async (ctx) => {
    required(ctx.body, ['username']);
    const username = String(ctx.body.username).trim().toLowerCase();
    const [u] = await sql`SELECT id, username, full_name FROM user_account WHERE lower(username) = ${username}`;
    if (u) {
      await notify({
        role: 'admin',
        title: 'Solicitud de recuperación de contraseña',
        body: `${u.full_name || u.username} (${u.username}) solicitó restablecer su contraseña. Use "Restablecer contraseña" en Usuarios.`,
        kind: 'recuperacion',
      });
      await audit(null, u.id, 'solicitud_recuperacion', 'user_account', u.id);
    }
    return {
      ok: true,
      message: 'Si el usuario existe, la administración recibió la solicitud y le entregará una contraseña temporal.',
    };
  });
}
