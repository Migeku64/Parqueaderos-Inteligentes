// Autenticación: hash de contraseñas (scrypt), JWT HS256 y control de acceso por roles.
import crypto from 'node:crypto';
import { promisify } from 'node:util';
import { config } from './config.js';
import { sql } from './db.js';
import { HttpError } from './http.js';

const scrypt = promisify(crypto.scrypt);

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = await scrypt(String(password), salt, 64);
  return `scrypt$${salt.toString('base64')}$${hash.toString('base64')}`;
}

export async function verifyPassword(password, stored) {
  const [alg, saltB64, hashB64] = String(stored || '').split('$');
  if (alg !== 'scrypt' || !saltB64 || !hashB64) return false;
  const expected = Buffer.from(hashB64, 'base64');
  const actual = await scrypt(String(password), Buffer.from(saltB64, 'base64'), expected.length);
  return crypto.timingSafeEqual(expected, actual);
}

export function validatePassword(pw) {
  if (typeof pw !== 'string' || pw.length < 6) {
    throw new HttpError(400, 'La contraseña debe tener al menos 6 caracteres');
  }
}

export function randomPassword() {
  // 10 caracteres legibles (sin 0/O/1/l)
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let out = '';
  for (let i = 0; i < 10; i++) out += alphabet[crypto.randomInt(alphabet.length)];
  return out;
}

const b64url = (buf) => Buffer.from(buf).toString('base64url');

export function signToken(payload) {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const now = Math.floor(Date.now() / 1000);
  const body = b64url(JSON.stringify({ ...payload, iat: now, exp: now + config.jwtHours * 3600 }));
  const sig = crypto.createHmac('sha256', config.jwtSecret).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

export function verifyToken(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  const [header, body, sig] = parts;
  const expected = crypto.createHmac('sha256', config.jwtSecret).update(`${header}.${body}`).digest();
  const given = Buffer.from(sig, 'base64url');
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

/** Carga el usuario del token y verifica que siga activo y sin bloqueo. */
export async function userFromToken(token) {
  const payload = verifyToken(token);
  if (!payload) return null;
  const [user] = await sql`
    SELECT id, username, full_name, role, resident_id, is_active, is_blocked, must_change_password
    FROM user_account WHERE id = ${payload.sub}`;
  if (!user || !user.is_active || user.is_blocked) return null;
  return user;
}

export async function requireAuth(ctx) {
  const header = ctx.req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const user = token ? await userFromToken(token) : null;
  if (!user) throw new HttpError(401, 'Sesión inválida o expirada. Inicie sesión nuevamente.');
  ctx.user = user;
}

export function requireRole(...roles) {
  return async (ctx) => {
    if (!ctx.user) await requireAuth(ctx);
    if (!roles.includes(ctx.user.role)) {
      throw new HttpError(403, 'No tiene permisos para realizar esta acción');
    }
  };
}

export const ADMIN = requireRole('admin');
export const STAFF = requireRole('admin', 'guarda');
export const ANY = requireAuth;
