import http from 'node:http';
import { Router, createHandler } from './http.js';
import { attachWebSocket } from './ws.js';
import authRoutes from './routes/auth.js';
import userRoutes from './routes/users.js';
import residentRoutes from './routes/residents.js';
import spotRoutes from './routes/spots.js';
import cycleRoutes from './routes/cycles.js';
import movementRoutes from './routes/movements.js';
import reportRoutes from './routes/reports.js';
import miscRoutes from './routes/misc.js';
import { sql } from './db.js';

export function createRouter() {
  const r = new Router();
  r.get('/', async () => ({ name: 'API Parqueadero Comunitario', status: 'ok' }));
  r.get('/health', async () => {
    await sql`SELECT 1`;
    return { status: 'ok', time: new Date().toISOString() };
  });
  for (const register of [
    authRoutes,
    userRoutes,
    residentRoutes,
    spotRoutes,
    cycleRoutes,
    movementRoutes,
    reportRoutes,
    miscRoutes,
  ]) {
    register(r);
  }
  return r;
}

export function createServer() {
  const server = http.createServer(createHandler(createRouter()));
  attachWebSocket(server);
  return server;
}
