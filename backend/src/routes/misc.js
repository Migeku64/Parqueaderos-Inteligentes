// Vista del residente, notificaciones (RF13), auditoría (RF15) y respaldos (RF20).
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { sql } from '../db.js';
import { notFound, intParam } from '../http.js';
import { ADMIN, ANY, requireRole } from '../auth.js';
import { audit } from '../events.js';
import { runBackup, backupPath } from '../services/backup.js';
import { evaluateResidents } from '../services/draw.js';
import { getResident } from './residents.js';

const RESIDENT = requireRole('residente');

export default function miscRoutes(r) {
  // ---------- Resumen para el residente (pantallas "Residente" y "Sorteos" del mockup) ----------
  r.get('/me/summary', RESIDENT, async (ctx) => {
    const res = await getResident(ctx.user.resident_id);
    if (!res) throw notFound('Residente no encontrado');
    const [active] = await sql`SELECT * FROM ciclo WHERE estado = 'activo'`;
    const [next] = await sql`SELECT * FROM ciclo WHERE estado = 'planeado' ORDER BY fecha_inicio LIMIT 1`;
    const history = await sql`
      SELECT c.nombre AS cycle_name, c.fecha_inicio, c.fecha_fin, s.codigo AS spot_code, pa.estado, pa.metodo, pa.puntaje_ipa
      FROM asignacion pa JOIN ciclo c ON c.id = pa.ciclo_id JOIN celda s ON s.id = pa.celda_id
      WHERE pa.residente_id = ${res.id} ORDER BY c.fecha_inicio DESC LIMIT 20`;
    const [nextAssignment] = next
      ? await sql`SELECT s.codigo AS spot_code FROM asignacion pa JOIN celda s ON s.id = pa.celda_id
                  WHERE pa.ciclo_id = ${next.id} AND pa.residente_id = ${res.id} AND pa.estado = 'vigente'`
      : [];

    // Prioridad estimada para el próximo sorteo
    let priority = null;
    if (next) {
      const { eligible, excluded } = await evaluateResidents(next);
      const mine = eligible.find((e) => e.resident_id === res.id);
      const ex = excluded.find((e) => e.resident_id === res.id);
      priority = mine
        ? { eligible: true, ipa: mine.ipa, components: mine.components, position: eligible.indexOf(mine) + 1, of: eligible.length }
        : { eligible: false, reasons: ex ? ex.reasons : [], ipa: ex?.ipa, components: ex?.components };
    }

    const current = res.current_assignment;
    return {
      resident: {
        id: res.id,
        full_name: res.full_name,
        house: res.house,
        document_number: res.document_number,
        phone: res.phone,
        email: res.email,
        status: res.status,
        debt: Number(res.debt),
      },
      vehicles: res.vehicles,
      turn_status: current ? 'ACTIVO' : nextAssignment ? 'PRÓXIMO' : 'INACTIVO',
      current_assignment: current,
      next_assignment: nextAssignment ? { ...nextAssignment, cycle_name: next.name, start_date: next.start_date } : null,
      active_cycle: active || null,
      next_cycle: next || null,
      next_draw_date: next?.draw_date || null,
      priority,
      history,
    };
  });

  // ---------- Notificaciones ----------
  r.get('/notifications', ANY, async (ctx) => {
    const items = await sql`
      SELECT id, titulo, cuerpo, categoria, creado_en, leido_en FROM notificacion
      WHERE cuenta_usuario_id = ${ctx.user.id} ORDER BY creado_en DESC, id DESC LIMIT 100`;
    const [{ unread }] = await sql`
      SELECT count(*)::int AS unread FROM notificacion WHERE cuenta_usuario_id = ${ctx.user.id} AND leido_en IS NULL`;
    return { unread, items };
  });

  r.post('/notifications/:id/read', ANY, async (ctx) => {
    await sql`UPDATE notificacion SET leido_en = now()
              WHERE id = ${intParam(ctx.params.id)} AND cuenta_usuario_id = ${ctx.user.id} AND leido_en IS NULL`;
    return { ok: true };
  });

  r.post('/notifications/read-all', ANY, async (ctx) => {
    await sql`UPDATE notificacion SET leido_en = now() WHERE cuenta_usuario_id = ${ctx.user.id} AND leido_en IS NULL`;
    return { ok: true };
  });

  // ---------- Auditoría ----------
  r.get('/audit', ADMIN, async (ctx) => {
    const q = ctx.query;
    const limit = Math.min(Number(q.limit) || 200, 1000);
    return sql`
      SELECT a.id, a.accion, a.entidad, a.entidad_id, a.realizado_en, a.detalles, u.usuario
      FROM auditoria a LEFT JOIN cuenta_usuario u ON u.id = a.cuenta_usuario_id
      WHERE (${q.action || null}::text IS NULL OR a.accion = ${q.action || null})
        AND (${q.from || null}::date IS NULL OR a.realizado_en >= ${q.from || null}::date)
        AND (${q.to || null}::date IS NULL OR a.realizado_en < ${q.to || null}::date + 1)
      ORDER BY a.realizado_en DESC, a.id DESC LIMIT ${limit}`;
  });

  // ---------- Respaldos ----------
  r.get('/backups', ADMIN, async () => sql`SELECT * FROM respaldo ORDER BY creado_en DESC LIMIT 100`);

  r.post('/backups', ADMIN, async (ctx) => {
    const rec = await runBackup('manual');
    await audit(null, ctx.user.id, 'respaldo_manual', 'respaldo', rec.id, { archivo: rec.file_name, estado: rec.status });
    ctx.status = 201;
    return rec;
  });

  r.get('/backups/:id/download', ADMIN, async (ctx) => {
    const [rec] = await sql`SELECT * FROM respaldo WHERE id = ${intParam(ctx.params.id)} AND estado = 'ok'`;
    const file = rec && backupPath(rec.file_name);
    if (!file) throw notFound('Respaldo no encontrado');
    try {
      const { size } = await stat(file);
      ctx.sent = true;
      ctx.res.writeHead(200, {
        'Content-Type': 'application/json',
        'Content-Length': size,
        'Content-Disposition': `attachment; filename="${rec.file_name}"`,
      });
      createReadStream(file).pipe(ctx.res);
    } catch {
      throw notFound('El archivo del respaldo ya no existe');
    }
  });
}
