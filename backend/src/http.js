// Mini-framework HTTP sin dependencias: enrutador, JSON, CORS y manejo de errores.
import { config } from './config.js';

export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export const badRequest = (msg, details) => new HttpError(400, msg, details);
export const notFound = (msg = 'Recurso no encontrado') => new HttpError(404, msg);
export const conflict = (msg) => new HttpError(409, msg);

export class Router {
  constructor() {
    this.routes = [];
  }

  add(method, pattern, ...handlers) {
    const keys = [];
    const regex = new RegExp(
      '^' +
        pattern.replace(/\/:([a-zA-Z_]+)/g, (_, k) => {
          keys.push(k);
          return '/([^/]+)';
        }) +
        '/?$',
    );
    this.routes.push({ method, regex, keys, handlers });
    return this;
  }

  get(p, ...h) { return this.add('GET', p, ...h); }
  post(p, ...h) { return this.add('POST', p, ...h); }
  put(p, ...h) { return this.add('PUT', p, ...h); }
  patch(p, ...h) { return this.add('PATCH', p, ...h); }
  delete(p, ...h) { return this.add('DELETE', p, ...h); }

  match(method, pathname) {
    let pathMatched = false;
    for (const r of this.routes) {
      const m = pathname.match(r.regex);
      if (!m) continue;
      pathMatched = true;
      if (r.method !== method) continue;
      const params = {};
      r.keys.forEach((k, i) => (params[k] = decodeURIComponent(m[i + 1])));
      return { route: r, params };
    }
    return { route: null, pathMatched };
  }
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 1_000_000) throw new HttpError(413, 'El cuerpo de la petición es demasiado grande');
    chunks.push(chunk);
  }
  if (!size) return {};
  const text = Buffer.concat(chunks).toString('utf8');
  try {
    return JSON.parse(text);
  } catch {
    throw badRequest('JSON inválido');
  }
}

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', config.corsOrigin);
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Device-Key');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
}

export function createHandler(router) {
  return async (req, res) => {
    setCors(res);
    if (req.method === 'OPTIONS') {
      res.writeHead(204).end();
      return;
    }
    const url = new URL(req.url, 'http://localhost');
    const ctx = {
      req,
      res,
      method: req.method,
      path: url.pathname,
      query: Object.fromEntries(url.searchParams),
      params: {},
      body: {},
      user: null,
      sent: false,
      json(status, data) {
        if (this.sent) return;
        this.sent = true;
        res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify(data));
      },
      send(status, body, contentType, extraHeaders = {}) {
        if (this.sent) return;
        this.sent = true;
        res.writeHead(status, { 'Content-Type': contentType, ...extraHeaders });
        res.end(body);
      },
    };
    try {
      const { route, params, pathMatched } = router.match(req.method, url.pathname);
      if (!route) {
        throw pathMatched ? new HttpError(405, 'Método no permitido') : notFound('Ruta no encontrada');
      }
      ctx.params = params;
      if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) ctx.body = await readBody(req);
      for (const h of route.handlers) {
        const result = await h(ctx);
        if (ctx.sent) return;
        if (result !== undefined) {
          ctx.json(ctx.status || 200, result);
          return;
        }
      }
      if (!ctx.sent) ctx.json(204, {});
    } catch (err) {
      handleError(ctx, err);
    }
  };
}

function handleError(ctx, err) {
  if (err instanceof HttpError) {
    ctx.json(err.status, { error: err.message, details: err.details });
    return;
  }
  // Errores de PostgreSQL más comunes -> mensajes comprensibles
  if (err && err.code === '23505') {
    ctx.json(409, { error: 'Ya existe un registro con esos datos', details: err.detail });
    return;
  }
  if (err && err.code === '23503') {
    ctx.json(409, { error: 'El registro está relacionado con otros datos', details: err.detail });
    return;
  }
  if (err && (err.code === '23514' || err.code === '22P02' || err.code === '22007' || err.code === '22008')) {
    ctx.json(400, { error: 'Datos inválidos', details: err.message });
    return;
  }
  console.error('[error]', err);
  ctx.json(500, { error: 'Error interno del servidor' });
}

// ---------- Validación sencilla ----------
export function required(body, fields) {
  const missing = fields.filter((f) => body[f] === undefined || body[f] === null || String(body[f]).trim() === '');
  if (missing.length) throw badRequest(`Campos obligatorios: ${missing.join(', ')}`);
}

export function intParam(v, name = 'id') {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) throw badRequest(`${name} inválido`);
  return n;
}

export function normalizePlate(p) {
  return String(p || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export function isDate(s) {
  return typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s));
}

export function toCsv(rows, columns) {
  const esc = (v) => {
    if (v === null || v === undefined) return '';
    const s = v instanceof Date ? v.toISOString() : String(v);
    return /[",;\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const cols = columns || (rows[0] ? Object.keys(rows[0]).map((k) => ({ key: k, label: k })) : []);
  const lines = [cols.map((c) => esc(c.label)).join(',')];
  for (const r of rows) lines.push(cols.map((c) => esc(r[c.key])).join(','));
  return '﻿' + lines.join('\r\n');
}
