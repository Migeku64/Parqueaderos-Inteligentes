// Pruebas de integración contra una base PostgreSQL real.
// Uso: DATABASE_URL=postgres://.../parqueadero_test npm test
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'secreto-de-pruebas';
process.env.BACKUP_DIR = path.join(process.env.TMPDIR || '/tmp', 'parq-test-backups');
process.env.PLATE_READER_KEY = 'lector-123';
if (!process.env.DATABASE_URL) process.env.DATABASE_URL = 'postgres://postgres@127.0.0.1:5432/parqueadero_test';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
execFileSync('node', ['scripts/migrate.js', '--reset'], { cwd: root, env: process.env, stdio: 'ignore' });
execFileSync('node', ['scripts/seed.js'], { cwd: root, env: process.env, stdio: 'ignore' });

const { createServer } = await import('../src/app.js');
const { sql } = await import('../src/db.js');
const { computeIpa, drawOrder, matchSpots } = await import('../src/services/draw.js');

let server;
let base;
const tokens = {};

async function api(method, url, body, who = 'admin', headers = {}) {
  const res = await fetch(base + url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(who && tokens[who] ? { Authorization: `Bearer ${tokens[who]}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }
  return { status: res.status, data };
}

before(async () => {
  server = createServer();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
  for (const [who, user, pw] of [
    ['admin', 'admin', 'admin123'],
    ['guarda', 'guarda', 'guarda123'],
    ['res', 'casa150', 'residente123'], ['admin2', 'acardona', 'admin123'],
  ]) {
    const { status, data } = await api('POST', '/auth/login', { username: user, password: pw }, null);
    assert.equal(status, 200, `login ${user}`);
    tokens[who] = data.token;
  }
});

after(async () => {
  server.closeAllConnections?.();
  server.close();
  await sql.end({ timeout: 2 });
});

test('fórmula IPA = (Te + Pa + Hn) / (Cu + 1)', () => {
  assert.equal(computeIpa({ te: 6, pa: 2, hn: 4, cu: 0 }), 12);
  assert.equal(computeIpa({ te: 6, pa: 2, hn: 4, cu: 2 }), 4);
  assert.equal(computeIpa({ te: 1, pa: 0, hn: 1, cu: 2 }), 0.667);
});

test('sorteo por prioridad respeta el IPA y las celdas para discapacidad', () => {
  const el = [
    { resident_id: 1, ipa: 1, has_disability: false },
    { resident_id: 2, ipa: 9, has_disability: false },
    { resident_id: 3, ipa: 5, has_disability: true },
  ];
  const order = drawOrder(el, 'prioridad');
  assert.deepEqual(order.map((e) => e.resident_id), [2, 3, 1]);
  const { proposal, waitlist } = matchSpots(order, [
    { id: 10, code: 'D01', is_disabled_spot: true },
    { id: 11, code: 'D02', is_disabled_spot: false },
  ]);
  assert.equal(proposal.find((p) => p.resident_id === 3).spot.code, 'D01');
  assert.equal(proposal.find((p) => p.resident_id === 2).spot.code, 'D02');
  assert.deepEqual(waitlist.map((w) => w.resident_id), [1]);
});

test('sorteo ponderado incluye a todos sin repetir', () => {
  const el = Array.from({ length: 30 }, (_, i) => ({ resident_id: i + 1, ipa: i % 5 }));
  const order = drawOrder(el, 'ponderado');
  assert.equal(new Set(order.map((e) => e.resident_id)).size, 30);
});

test('login incorrecto y bloqueo tras 5 intentos', async () => {
  for (let i = 0; i < 4; i++) {
    const r = await api('POST', '/auth/login', { username: 'casa101', password: 'mala' }, null);
    assert.equal(r.status, 401);
  }
  const r5 = await api('POST', '/auth/login', { username: 'casa101', password: 'mala' }, null);
  assert.equal(r5.status, 423);
  const ok = await api('POST', '/auth/login', { username: 'casa101', password: 'residente123' }, null);
  assert.equal(ok.status, 423, 'sigue bloqueado aunque la clave sea correcta');
  const users = await api('GET', '/users');
  const jp = users.data.find((u) => u.username === 'casa101');
  assert.equal(jp.is_blocked, true);
  const reset = await api('POST', `/users/${jp.id}/reset-password`, {});
  assert.equal(reset.status, 200);
  const again = await api('POST', '/auth/login', { username: 'casa101', password: reset.data.temporary_password }, null);
  assert.equal(again.status, 200);
  assert.equal(again.data.user.must_change_password, true);
});

test('los autores tienen rol de administrador', async () => {
  const users = await api('GET', '/users', null, 'admin2');
  assert.equal(users.status, 200);
  for (const u of ['mpinilla', 'acardona', 'jmontoya']) {
    assert.equal(users.data.find((x) => x.username === u).role, 'admin', u);
  }
});

test('control de acceso por roles', async () => {
  assert.equal((await api('GET', '/users', null, 'guarda')).status, 403);
  assert.equal((await api('GET', '/residents', null, 'res')).status, 403);
  assert.equal((await api('GET', '/residents', null, null)).status, 401);
  assert.equal((await api('GET', '/dashboard', null, 'guarda')).status, 200);
});

test('CRUD de residentes y vehículos con búsqueda', async () => {
  const c = await api('POST', '/residents', {
    full_name: 'Prueba Uno',
    document_number: '999000111',
    house_number: '299',
    vehicle: { plate: 'prb-123', type: 'carro' },
    account: { username: 'prueba1', password: 'secreta1' },
  });
  assert.equal(c.status, 201, JSON.stringify(c.data));
  assert.equal(c.data.vehicles[0].plate, 'PRB123');
  assert.equal(c.data.house, '299');
  const out = await api('POST', '/residents', { full_name: 'X', document_number: '55', house_number: '301' });
  assert.equal(out.status, 400, 'casa fuera del rango 1-300');
  const dup = await api('POST', '/residents', { full_name: 'X', document_number: '999000111', house_number: '1' });
  assert.equal(dup.status, 409);
  const search = await api('GET', '/residents?q=PRB123');
  assert.equal(search.data.length, 1);
  const upd = await api('PUT', `/residents/${c.data.id}`, { debt: 50000, phone: '3001234567' });
  assert.equal(Number(upd.data.debt), 50000);
  const v = await api('POST', `/residents/${c.data.id}/vehicles`, { plate: 'MOT12A', type: 'moto' });
  assert.equal(v.status, 201);
  const bad = await api('POST', `/residents/${c.data.id}/vehicles`, { plate: '!!' });
  assert.equal(bad.status, 400);
  const detail = await api('GET', `/residents/${c.data.id}`);
  assert.equal(detail.data.vehicles.length, 2);
});

test('mapa de celdas y resumen', async () => {
  const spots = await api('GET', '/spots', null, 'guarda');
  assert.equal(spots.data.length, 50);
  assert.ok(spots.data.some((s) => s.state === 'ocupada'));
  const resSpots = await api('GET', '/spots', null, 'res');
  assert.equal(resSpots.data[0].resident_name, undefined, 'el residente no ve datos de otros');
  const bulk = await api('POST', '/spots/bulk', { prefix: 'M', from: 1, to: 3 });
  assert.equal(bulk.data.created, 3);
});

test('entrada autorizada, doble entrada, salida e ingreso no autorizado', async () => {
  const cyc = await api('GET', '/cycles');
  const active = cyc.data.find((c) => c.status === 'activo');
  const detail = await api('GET', `/cycles/${active.id}`);
  const parked = await sql`SELECT DISTINCT plate FROM vehicle_movement`;
  const free = detail.data.assignment_list.find((a) => !parked.some((p) => p.plate === a.plate));
  assert.ok(free, 'hay un asignado fuera del conjunto');

  const check = await api('GET', `/movements/check/${free.plate}`, null, 'guarda');
  assert.equal(check.data.can_enter, true);

  const e1 = await api('POST', '/movements', { plate: free.plate.toLowerCase(), type: 'entrada' }, 'guarda');
  assert.equal(e1.status, 201);
  assert.equal(e1.data.authorized, true);
  assert.equal(e1.data.spot_code, free.spot_code);

  const e2 = await api('POST', '/movements', { plate: free.plate, type: 'entrada' }, 'guarda');
  assert.equal(e2.status, 409);

  const s1 = await api('POST', '/movements', { plate: free.plate, type: 'salida' }, 'guarda');
  assert.equal(s1.status, 201);
  const [spot] = await sql`SELECT is_occupied FROM parking_spot WHERE code = ${free.spot_code}`;
  assert.equal(spot.is_occupied, false);

  const bad = await api('POST', '/movements', { plate: 'ZZZ999', type: 'entrada' }, 'guarda');
  assert.equal(bad.data.authorized, false);
  const notif = await api('GET', '/notifications');
  assert.ok(notif.data.items.some((n) => n.title.includes('ZZZ999')));

  const reader = await api('POST', '/movements/reader', { plate: free.plate, type: 'entrada' }, null, { 'X-Device-Key': 'lector-123' });
  assert.equal(reader.status, 201);
  assert.equal(reader.data.movement.source, 'lector');
  const readerBad = await api('POST', '/movements/reader', { plate: free.plate, type: 'salida' }, null, { 'X-Device-Key': 'x' });
  assert.equal(readerBad.status, 401);
});

test('sorteo del próximo ciclo: preview, reglas de elegibilidad y confirmación', async () => {
  const cyc = await api('GET', '/cycles');
  const next = cyc.data.find((c) => c.status === 'planeado');
  const active = cyc.data.find((c) => c.status === 'activo');
  const pv = await api('POST', `/cycles/${next.id}/draw/preview`, { mode: 'prioridad' });
  assert.equal(pv.status, 200, JSON.stringify(pv.data));
  assert.ok(pv.data.proposal.length > 0);
  assert.ok(pv.data.proposal.length <= pv.data.spots_available);

  // Nadie que tenga parqueadero en el ciclo activo (ciclo anterior al sorteado) puede repetir
  const activeDetail = await api('GET', `/cycles/${active.id}`);
  const activeResidents = new Set(activeDetail.data.assignment_list.map((a) => a.resident_id));
  assert.ok(pv.data.proposal.every((p) => !activeResidents.has(p.resident_id)));
  assert.ok(pv.data.excluded.some((x) => x.reasons.includes('Usó el parqueadero en el ciclo anterior')));
  assert.ok(pv.data.excluded.some((x) => x.reasons.includes('Tiene deuda con la administración')));
  assert.ok(pv.data.excluded.some((x) => x.reasons.includes('No tiene vehículo activo registrado')));

  // El orden de prioridad es no creciente en IPA
  const ipas = pv.data.proposal.map((p) => p.ipa);
  assert.deepEqual(ipas, [...ipas].sort((a, b) => b - a));

  // Confirmar la propuesta tal como la vio el administrador
  const proposal = pv.data.proposal.map((p) => ({ resident_id: p.resident_id, parking_spot_id: p.parking_spot_id }));
  const conf = await api('POST', `/cycles/${next.id}/draw`, { mode: 'prioridad', proposal });
  assert.equal(conf.status, 201, JSON.stringify(conf.data));
  assert.equal(conf.data.assigned.length, proposal.length);

  // No se puede asignar dos veces la misma celda
  const again = await api('POST', `/cycles/${next.id}/draw`, { proposal: [proposal[0]] });
  assert.equal(again.status, 400);
});

test('vista del residente', async () => {
  const me = await api('GET', '/me/summary', null, 'res');
  assert.equal(me.status, 200, JSON.stringify(me.data));
  assert.equal(me.data.resident.full_name, 'Miguel Ángel Pinilla');
  assert.ok(['ACTIVO', 'INACTIVO', 'PRÓXIMO'].includes(me.data.turn_status));
  assert.ok(me.data.vehicles.length >= 1);
});

test('reportes JSON y CSV, auditoría, dashboard y respaldo', async () => {
  for (const t of ['ocupacion', 'ciclos', 'asignaciones', 'movimientos']) {
    const r = await api('GET', `/reports/${t}`);
    assert.equal(r.status, 200, `${t}: ${JSON.stringify(r.data)}`);
    assert.ok(Array.isArray(r.data.rows));
  }
  const csv = await api('GET', '/reports/movimientos?format=csv');
  assert.equal(typeof csv.data, 'string');
  assert.ok(csv.data.includes('Placa'));

  const dash = await api('GET', '/dashboard');
  assert.equal(dash.data.spots.total, 53);
  assert.equal(dash.data.entries_last_7_days.length, 7);

  const audit = await api('GET', '/audit?action=sorteo');
  assert.ok(audit.data.length >= 1);

  const b = await api('POST', '/backups', {});
  assert.equal(b.status, 201);
  assert.equal(b.data.status, 'ok');
  const dl = await fetch(`${base}/backups/${b.data.id}/download`, { headers: { Authorization: `Bearer ${tokens.admin}` } });
  const json = await dl.json();
  assert.ok(json.tables.resident.length >= 300);
});

test('ciclos: validación de fechas, cierre y activación', async () => {
  const bad = await api('POST', '/cycles', { name: 'X', start_date: '2030-01-01', end_date: '2030-01-05' });
  assert.equal(bad.status, 400);
  const cyc = await api('GET', '/cycles');
  const active = cyc.data.find((c) => c.status === 'activo');
  const next = cyc.data.find((c) => c.status === 'planeado');
  assert.equal((await api('POST', `/cycles/${next.id}/activate`, {})).status, 409);
  const closed = await api('POST', `/cycles/${active.id}/close`, {});
  assert.equal(closed.status, 200);
  assert.ok(closed.data.released > 0);
  const act = await api('POST', `/cycles/${next.id}/activate`, {});
  assert.equal(act.status, 200);
  assert.equal(act.data.status, 'activo');
});

test('WebSocket en tiempo real recibe eventos', async () => {
  const ws = new WebSocket(`${base.replace('http', 'ws')}/ws?token=${tokens.guarda}`);
  const events = [];
  await new Promise((resolve, reject) => {
    ws.onopen = resolve;
    ws.onerror = reject;
  });
  ws.onmessage = (m) => events.push(JSON.parse(m.data).event);
  await new Promise((r) => setTimeout(r, 100));
  await api('POST', '/movements', { plate: 'NOEXIS1', type: 'entrada' }, 'guarda');
  await new Promise((r) => setTimeout(r, 300));
  ws.close();
  assert.ok(events.includes('hello'));
  assert.ok(events.includes('movement'));
  assert.ok(events.includes('spots'));
});

test('cambio de contraseña', async () => {
  const r = await api('POST', '/auth/change-password', { current_password: 'residente123', new_password: 'nueva123' }, 'res');
  assert.equal(r.status, 200);
  const login = await api('POST', '/auth/login', { username: 'casa150', password: 'nueva123' }, null);
  assert.equal(login.status, 200);
});
