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

// Servidor que simula la API de Brevo para probar los correos sin enviarlos de verdad
import http from 'node:http';
const sentMails = [];
const brevo = http.createServer((req, res) => {
  let data = '';
  req.on('data', (c) => (data += c));
  req.on('end', () => {
    sentMails.push({ key: req.headers['api-key'], body: JSON.parse(data) });
    res.writeHead(201, { 'Content-Type': 'application/json' });
    res.end('{"messageId":"<prueba>"}');
  });
});
await new Promise((r) => brevo.listen(0, '127.0.0.1', r));
process.env.BREVO_API_KEY = 'clave-brevo-prueba';
process.env.BREVO_API_URL = `http://127.0.0.1:${brevo.address().port}/v3/smtp/email`;
process.env.EMAIL_FROM = 'parqueadero@prueba.co';
process.env.EMAIL_ADMINS = 'admin1@prueba.co, admin2@prueba.co';
process.env.EMAIL_DELAY_MS = '20';

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

test('eliminar celdas: solo las que nunca se han usado', async () => {
  const z = await api('POST', '/spots/bulk', { prefix: 'Z', from: 1, to: 3 });
  assert.equal(z.data.created, 3);
  const all = await api('GET', '/spots');
  const z01 = all.data.find((s) => s.code === 'Z01');
  // El guarda no puede eliminar celdas
  assert.equal((await api('DELETE', `/spots/${z01.id}`, null, 'guarda')).status, 403);
  const del = await api('DELETE', `/spots/${z01.id}`);
  assert.equal(del.status, 200);
  assert.equal((await api('DELETE', `/spots/${z01.id}`)).status, 404);
  // Una celda con asignaciones (historial) no se elimina: se debe desactivar
  const used = all.data.find((s) => s.assignment_id);
  assert.ok(used, 'hay una celda asignada');
  const blocked = await api('DELETE', `/spots/${used.id}`);
  assert.equal(blocked.status, 409);
  // Por rango: elimina Z02 y Z03 y no toca las celdas con historial
  const range = await api('POST', '/spots/bulk-delete', { prefix: 'Z', from: 1, to: 3 });
  assert.equal(range.data.deleted, 2);
  assert.equal(range.data.kept, 0);
  const [, pre, num] = used.code.match(/^(\D*)(\d+)$/);
  const keep = await api('POST', '/spots/bulk-delete', { prefix: pre, from: Number(num), to: Number(num) });
  assert.equal(keep.data.deleted, 0);
  assert.equal(keep.data.kept, 1, 'la celda usada se conserva');
  const after = await api('GET', '/spots');
  assert.ok(after.data.some((s) => s.id === used.id));
  assert.ok(!after.data.some((s) => s.code.startsWith('Z')));
});

test('eliminar residentes, vehículos, usuarios y ciclos creados por error', async () => {
  // Residente nuevo con cuenta y vehículo: se puede eliminar porque nunca se ha usado
  const c = await api('POST', '/residents', {
    full_name: 'Registro Equivocado',
    document_number: '888000222',
    house_number: '298',
    vehicle: { plate: 'ERR111', type: 'carro' },
    account: { username: 'equivocado', password: 'secreta1' },
  });
  assert.equal(c.status, 201, JSON.stringify(c.data));
  const v2 = await api('POST', `/residents/${c.data.id}/vehicles`, { plate: 'ERR222', type: 'moto' });
  assert.equal((await api('DELETE', `/vehicles/${v2.data.id}/permanent`, null, 'guarda')).status, 403);
  assert.equal((await api('DELETE', `/vehicles/${v2.data.id}/permanent`)).status, 200);
  assert.equal((await api('DELETE', `/residents/${c.data.id}/permanent`)).status, 200);
  assert.equal((await api('GET', `/residents/${c.data.id}`)).status, 404);
  const [acc] = await sql`SELECT id FROM cuenta_usuario WHERE usuario = 'equivocado'`;
  assert.equal(acc, undefined, 'la cuenta del residente también se elimina');

  // Un residente o vehículo con asignaciones no se elimina: se debe inactivar o retirar
  const [used] = await sql`SELECT residente_id, vehiculo_id FROM asignacion LIMIT 1`;
  assert.equal((await api('DELETE', `/residents/${used.resident_id}/permanent`)).status, 409);
  assert.equal((await api('DELETE', `/vehicles/${used.vehicle_id}/permanent`)).status, 409);

  // Usuarios: se elimina una cuenta que nunca ingresó; no la propia ni una que ya ingresó
  const u = await api('POST', '/users', { username: 'guarda.error', password: 'secreta1', role: 'guarda', full_name: 'Guarda Error' });
  assert.equal(u.status, 201, JSON.stringify(u.data));
  assert.equal((await api('DELETE', `/users/${u.data.id}`)).status, 200);
  const users = await api('GET', '/users');
  const me = users.data.find((x) => x.username === 'admin');
  const guard = users.data.find((x) => x.username === 'guarda');
  assert.equal((await api('DELETE', `/users/${me.id}`)).status, 400);
  assert.equal((await api('DELETE', `/users/${guard.id}`)).status, 409);

  // Ciclos: solo los planeados sin asignaciones
  const cy = await api('POST', '/cycles', { name: 'Ciclo por error', start_date: '2031-01-01', end_date: '2031-03-01' });
  assert.equal(cy.status, 201, JSON.stringify(cy.data));
  assert.equal((await api('DELETE', `/cycles/${cy.data.id}`)).status, 200);
  const cycles = await api('GET', '/cycles');
  const active = cycles.data.find((x) => x.status === 'activo');
  assert.equal((await api('DELETE', `/cycles/${active.id}`)).status, 409);
});

test('entrada autorizada, doble entrada, salida e ingreso no autorizado', async () => {
  const cyc = await api('GET', '/cycles');
  const active = cyc.data.find((c) => c.status === 'activo');
  const detail = await api('GET', `/cycles/${active.id}`);
  const parked = await sql`SELECT DISTINCT placa FROM movimiento_vehiculo`;
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
  const [spot] = await sql`SELECT ocupada FROM celda WHERE codigo = ${free.spot_code}`;
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

  // La asignación manual aplica la misma regla: quien usó el ciclo anterior no repite,
  // salvo una excepción con motivo, que queda registrada.
  const repeated = [...activeResidents][0];
  const freeSpot = pv.data.proposal[0].parking_spot_id;
  const blocked = await api('POST', '/assignments', { cycle_id: next.id, resident_id: repeated, parking_spot_id: freeSpot });
  assert.equal(blocked.status, 409, JSON.stringify(blocked.data));
  assert.equal(blocked.data.details.code, 'ciclo_anterior');
  const noReason = await api('POST', '/assignments', { cycle_id: next.id, resident_id: repeated, parking_spot_id: freeSpot, force: true });
  assert.equal(noReason.status, 400);
  const forced = await api('POST', '/assignments', {
    cycle_id: next.id, resident_id: repeated, parking_spot_id: freeSpot, force: true, reason: 'Caso de prueba',
  });
  assert.equal(forced.status, 201, JSON.stringify(forced.data));
  assert.ok(String(forced.data.notes).includes('Caso de prueba'));
  const canceled = await api('POST', `/assignments/${forced.data.id}/cancel`, { reason: 'prueba' });
  assert.equal(canceled.status, 200, JSON.stringify(canceled.data));

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
  for (const [fmt, magic, type] of [['pdf', '%PDF', 'application/pdf'], ['xlsx', 'PK', 'spreadsheetml']]) {
    for (const t of ['ocupacion', 'ciclos', 'asignaciones', 'movimientos']) {
      const res = await fetch(`${base}/reports/${t}?format=${fmt}`, { headers: { Authorization: `Bearer ${tokens.admin}` } });
      assert.equal(res.status, 200, `${t}.${fmt}`);
      assert.ok(res.headers.get('content-type').includes(type));
      assert.ok(res.headers.get('content-disposition').includes(`.${fmt}`));
      const buf = Buffer.from(await res.arrayBuffer());
      assert.equal(buf.subarray(0, magic.length).toString('latin1'), magic, `${t}.${fmt} firma`);
      if (process.env.EXPORT_DIR) (await import('node:fs')).writeFileSync(`${process.env.EXPORT_DIR}/${t}.${fmt}`, buf);
    }
  }
  const bad = await api('GET', '/reports/movimientos?format=doc');
  assert.equal(bad.status, 400);

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
  assert.ok(json.tables.residente.length >= 300);
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

test('sorteo automático en la fecha programada (una sola vez)', async () => {
  const hace2dias = new Date(Date.now() - 2 * 86400000).toISOString().slice(0, 10);
  // Ciclo con sorteo automático cuya fecha ya pasó
  const auto = await api('POST', '/cycles', {
    name: 'Auto 2030', start_date: '2030-02-01', end_date: '2030-05-01', draw_date: hace2dias, auto_draw: true,
  });
  assert.equal(auto.status, 201, JSON.stringify(auto.data));
  assert.equal(auto.data.auto_draw, true);
  // Ciclo sin sorteo automático: no se debe sortear solo
  const manual = await api('POST', '/cycles', {
    name: 'Manual 2030', start_date: '2030-06-01', end_date: '2030-09-01', draw_date: hace2dias,
  });
  assert.equal(manual.data.auto_draw, false);
  // Sin fecha de sorteo el sorteo automático no queda activo
  const sinFecha = await api('PATCH', `/cycles/${manual.data.id}`, { draw_date: null, auto_draw: true });
  assert.equal(sinFecha.data.auto_draw, false);

  const run = await api('POST', '/cycles/draws/run-scheduled', {});
  assert.equal(run.status, 200, JSON.stringify(run.data));
  assert.deepEqual(run.data.done.map((d) => d.cycle_id), [auto.data.id]);

  const detalle = await api('GET', `/cycles/${auto.data.id}`);
  assert.ok(detalle.data.draw_done_at, 'debe quedar marcado como sorteado');
  assert.equal(detalle.data.assignment_list.length, run.data.done[0].assigned);

  // Segunda revisión: no repite el sorteo
  const again = await api('POST', '/cycles/draws/run-scheduled', {});
  assert.deepEqual(again.data.done, []);

  const aud = await api('GET', '/audit?action=sorteo_automatico');
  assert.ok(aud.data.some((a) => a.entity_id === auto.data.id));
});

test('WebSocket en tiempo real recibe eventos', { skip: typeof WebSocket === 'undefined' && 'requiere Node 22+' }, async () => {
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

test('notificaciones por correo: residentes y administración (Brevo)', async () => {
  await new Promise((r) => setTimeout(r, 500));
  assert.ok(sentMails.length > 0, 'se enviaron correos');
  assert.ok(sentMails.every((m) => m.key === 'clave-brevo-prueba' && m.body.sender.email === 'parqueadero@prueba.co'));
  const toResident = sentMails.find((m) => m.body.to[0].email.endsWith('@correo.com'));
  assert.ok(toResident, 'correo a un residente');
  assert.ok(toResident.body.htmlContent.includes(toResident.body.subject.replace(/&/g, '&amp;')) || toResident.body.textContent.includes(toResident.body.subject));
  const toAdmins = sentMails.find((m) => m.body.to.length === 2 && m.body.to[0].email === 'admin1@prueba.co');
  assert.ok(toAdmins, 'alerta a la administración');
  const [{ n }] = await sql`SELECT count(*)::int AS n FROM notificacion WHERE correo_enviado_en IS NOT NULL`;
  assert.ok(n > 0, 'quedó registrada la fecha de envío');
});

test('auditoría automática: alertas, informe semanal y exportación', async () => {
  const { isNightHour, checkNightAdminLogin } = await import('../src/services/alerts.js');
  const { runScheduledAuditReport } = await import('../src/services/auditReport.js');
  const alert = async (tipo) =>
    (await sql`SELECT count(*)::int AS n FROM auditoria WHERE accion = 'alerta_seguridad' AND detalles->>'tipo' = ${tipo}`)[0].n;

  // 1) Ingresos rechazados repetidos de la misma placa: alerta al llegar a 3
  for (let i = 0; i < 3; i++) {
    const m = await api('POST', '/movements', { plate: 'XYZ999', type: 'entrada' }, 'guarda');
    assert.equal(m.data.authorized, false);
  }
  assert.equal(await alert('ingresos_rechazados'), 1);
  const [n1] = await sql`SELECT count(*)::int AS n FROM notificacion WHERE titulo LIKE 'Alerta de seguridad: ingresos rechazados de la placa XYZ999%'`;
  assert.ok(n1.n >= 1, 'la administración recibió la alerta');

  // 2) Eliminaciones seguidas del mismo usuario (las pruebas anteriores ya hicieron más de 5)
  assert.equal(await alert('eliminaciones_seguidas'), 1);

  // 3) Ingreso de un administrador en horario nocturno (hora de Colombia)
  assert.equal(isNightHour(new Date('2026-01-01T04:00:00Z')), true); // 11:00 p. m.
  assert.equal(isNightHour(new Date('2026-01-01T15:00:00Z')), false); // 10:00 a. m.
  const [adm] = await sql`SELECT * FROM cuenta_usuario WHERE usuario = 'admin'`;
  const nightBefore = await alert('ingreso_nocturno'); // puede haber otras si las pruebas corren de noche
  assert.equal(await checkNightAdminLogin(adm, new Date('2026-01-01T04:00:00Z')), true);
  assert.equal(await checkNightAdminLogin(adm, new Date('2026-01-01T15:00:00Z')), false);
  assert.equal(await alert('ingreso_nocturno'), nightBefore + 1);

  // Resumen e informe de auditoría
  const sum = await api('GET', '/audit/summary?days=7');
  assert.ok(sum.data.total > 0);
  assert.ok(sum.data.items.find((i) => i.key === 'eliminaciones').value > 0);
  assert.equal((await api('GET', '/audit/summary', null, 'guarda')).status, 403);
  const rep = await api('POST', '/audit/report', { days: 7 });
  assert.equal(rep.status, 200);
  const [n2] = await sql`SELECT count(*)::int AS n FROM notificacion WHERE categoria = 'informe_auditoria'`;
  assert.ok(n2.n >= 1);

  // Informe semanal automático: una sola vez por semana
  assert.equal(await runScheduledAuditReport(), true);
  assert.equal(await runScheduledAuditReport(), false);
  assert.equal(await runScheduledAuditReport(new Date(Date.now() + 9 * 86_400_000)), true);

  // Exportación de la auditoría a PDF, Excel y CSV
  for (const [fmt, magic] of [['pdf', '%PDF'], ['xlsx', 'PK'], ['csv', 'Fecha y hora']]) {
    const res = await fetch(`${base}/audit?format=${fmt}`, { headers: { Authorization: `Bearer ${tokens.admin}` } });
    assert.equal(res.status, 200, fmt);
    const buf = Buffer.from(await res.arrayBuffer());
    assert.ok(buf.subarray(0, 40).toString('utf8').replace(/^\uFEFF/, '').startsWith(magic), fmt);
  }
  assert.equal((await api('GET', '/audit?format=doc')).status, 400);
});

after(() => brevo.close());

