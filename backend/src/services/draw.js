// =====================================================================
//  Sorteo y asignación automática de parqueaderos (UC-04, RF03, RF09, RF17)
//
//  Índice de Prioridad de Asignación (Ecuación 1 del documento):
//
//              Te + Pa + Hn
//      IPA = ----------------
//                Cu + 1
//
//   Te = tiempo de espera: meses completos desde que terminó su último uso
//        del parqueadero (o desde su registro si nunca lo ha usado). Máx. 24.
//   Pa = puntaje administrativo (0 a 5) definido por la administración.
//   Hn = historial de no uso reciente: de los últimos 6 ciclos anteriores,
//        en cuántos NO tuvo parqueadero.
//   Cu = cantidad de ciclos en los que ya ha usado el parqueadero.
//
//  Reglas de elegibilidad (Capítulo I del documento):
//   * Residente activo y al día con la administración (deuda = 0).
//   * Tener al menos un vehículo activo registrado.
//   * NO haber tenido parqueadero en el ciclo anterior.
//   * Cuenta de usuario no bloqueada (si tiene).
//   * No tener ya una asignación vigente en el ciclo que se sortea.
//
//  Modos de sorteo:
//   * "ponderado" (por defecto): rifa en la que la probabilidad de salir
//     elegido es proporcional a (IPA + 1). Todos tienen opción, pero quien
//     más ha esperado tiene más probabilidad.
//   * "prioridad": se ordena por IPA de mayor a menor; los empates se
//     resuelven al azar.
//  Las celdas para personas con discapacidad se asignan primero a los
//  residentes elegibles que lo requieran.
// =====================================================================
import crypto from 'node:crypto';
import { sql, num } from '../db.js';
import { HttpError, badRequest } from '../http.js';

const HISTORY_WINDOW = 6;
const MAX_WAIT_MONTHS = 24;

export function computeIpa({ te, pa, hn, cu }) {
  return Math.round(((te + pa + hn) / (cu + 1)) * 1000) / 1000;
}

function monthsBetween(fromDate, toDate) {
  const a = new Date(fromDate);
  const b = new Date(toDate);
  let m = (b.getUTCFullYear() - a.getUTCFullYear()) * 12 + (b.getUTCMonth() - a.getUTCMonth());
  if (b.getUTCDate() < a.getUTCDate()) m -= 1;
  return Math.max(0, m);
}

export async function getCycle(id, db = sql) {
  const [cycle] = await db`SELECT * FROM cycle WHERE id = ${id}`;
  if (!cycle) throw new HttpError(404, 'Ciclo no encontrado');
  return cycle;
}

/**
 * Evalúa a todos los residentes para un ciclo: elegibilidad + componentes del IPA.
 */
export async function evaluateResidents(cycle, db = sql) {
  const previous = await db`
    SELECT id, start_date, end_date FROM cycle
    WHERE id <> ${cycle.id} AND start_date < ${cycle.start_date}
    ORDER BY start_date DESC LIMIT ${HISTORY_WINDOW}`;
  const previousIds = previous.map((c) => c.id);
  const lastCycleId = previousIds[0] ?? null;

  const residents = await db`
    SELECT r.id, r.full_name, r.status, r.debt, r.admin_score, r.has_disability, r.created_at,
           h.block, h.number AS house_number,
           ua.is_blocked,
           (SELECT json_agg(json_build_object('id', v.id, 'plate', v.plate, 'type', v.type) ORDER BY (v.type = 'moto'), v.id)
              FROM vehicle v WHERE v.resident_id = r.id AND v.is_active) AS vehicles
    FROM resident r
    JOIN house h ON h.id = r.house_id
    LEFT JOIN user_account ua ON ua.resident_id = r.id
    ORDER BY r.id`;

  const usage = await db`
    SELECT pa.resident_id, pa.cycle_id, pa.status, c.end_date, pa.released_at
    FROM parking_assignment pa JOIN cycle c ON c.id = pa.cycle_id
    WHERE pa.status IN ('vigente','finalizada')`;

  const byResident = new Map();
  for (const u of usage) {
    if (!byResident.has(u.resident_id)) byResident.set(u.resident_id, []);
    byResident.get(u.resident_id).push(u);
  }

  const eligible = [];
  const excluded = [];
  for (const r of residents) {
    const uses = byResident.get(r.id) || [];
    const reasons = [];
    if (r.status !== 'activo') reasons.push('Residente inactivo');
    if (num(r.debt) > 0) reasons.push('Tiene deuda con la administración');
    if (!r.vehicles || !r.vehicles.length) reasons.push('No tiene vehículo activo registrado');
    if (r.is_blocked) reasons.push('Usuario bloqueado');
    if (lastCycleId && uses.some((u) => u.cycle_id === lastCycleId)) reasons.push('Usó el parqueadero en el ciclo anterior');
    if (uses.some((u) => u.cycle_id === cycle.id && u.status === 'vigente')) reasons.push('Ya tiene asignación en este ciclo');

    const pastUses = uses.filter((u) => u.cycle_id !== cycle.id);
    const cu = pastUses.length;
    const lastEnd = pastUses
      .map((u) => (u.released_at ? new Date(u.released_at) : new Date(u.end_date)))
      .sort((a, b) => b - a)[0];
    const te = Math.min(MAX_WAIT_MONTHS, monthsBetween(lastEnd || r.created_at, cycle.start_date));
    const pa = Number(r.admin_score) || 0;
    const usedIds = new Set(pastUses.map((u) => u.cycle_id));
    const hn = previousIds.filter((id) => !usedIds.has(id)).length;
    const ipa = computeIpa({ te, pa, hn, cu });

    const item = {
      resident_id: r.id,
      full_name: r.full_name,
      house: r.block ? `${r.block}-${r.house_number}` : r.house_number,
      has_disability: r.has_disability,
      vehicle: r.vehicles && r.vehicles[0] ? r.vehicles[0] : null,
      components: { te, pa, hn, cu },
      ipa,
    };
    if (reasons.length) excluded.push({ ...item, reasons });
    else eligible.push(item);
  }
  eligible.sort((a, b) => b.ipa - a.ipa || a.full_name.localeCompare(b.full_name));
  return { eligible, excluded, previousCycleId: lastCycleId };
}

export async function availableSpots(cycleId, db = sql) {
  return db`
    SELECT s.id, s.code, s.is_disabled_spot
    FROM parking_spot s
    WHERE s.is_active
      AND NOT EXISTS (SELECT 1 FROM parking_assignment pa
                      WHERE pa.parking_spot_id = s.id AND pa.cycle_id = ${cycleId} AND pa.status = 'vigente')
    ORDER BY s.is_disabled_spot DESC, length(s.code), s.code`;
}

/** Ordena a los elegibles según el modo de sorteo. */
export function drawOrder(eligible, mode = 'ponderado', rand = (n) => crypto.randomInt(n)) {
  if (mode === 'prioridad') {
    // barajar primero para que los empates queden al azar, luego ordenar (sort es estable)
    const shuffled = [...eligible];
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = rand(i + 1);
      [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    return shuffled.sort((a, b) => b.ipa - a.ipa);
  }
  // ponderado: extracción sin reemplazo con peso (IPA + 1), en milésimas
  const pool = eligible.map((e) => ({ e, w: Math.max(1, Math.round((e.ipa + 1) * 1000)) }));
  const order = [];
  while (pool.length) {
    const total = pool.reduce((s, p) => s + p.w, 0);
    let ticket = rand(total);
    let idx = 0;
    while (ticket >= pool[idx].w) {
      ticket -= pool[idx].w;
      idx++;
    }
    order.push(pool[idx].e);
    pool.splice(idx, 1);
  }
  return order;
}

/** Empareja el orden del sorteo con las celdas disponibles. */
export function matchSpots(order, spots) {
  const disabledSpots = spots.filter((s) => s.is_disabled_spot);
  const normalSpots = spots.filter((s) => !s.is_disabled_spot);
  const proposal = [];
  const assigned = new Set();

  // 1) celdas para discapacidad -> residentes que lo requieren (en orden de sorteo)
  for (const e of order) {
    if (!disabledSpots.length) break;
    if (e.has_disability) {
      proposal.push({ ...e, spot: disabledSpots.shift() });
      assigned.add(e.resident_id);
    }
  }
  // 2) resto de celdas para los demás, en el orden del sorteo
  const remaining = [...normalSpots, ...disabledSpots];
  for (const e of order) {
    if (!remaining.length) break;
    if (assigned.has(e.resident_id)) continue;
    proposal.push({ ...e, spot: remaining.shift() });
    assigned.add(e.resident_id);
  }
  const waitlist = order.filter((e) => !assigned.has(e.resident_id));
  return { proposal, waitlist };
}

function assertDrawable(cycle) {
  if (cycle.status === 'cerrado') throw badRequest('No se puede sortear un ciclo cerrado');
}

export async function previewDraw(cycleId, mode = 'ponderado') {
  if (!['ponderado', 'prioridad'].includes(mode)) throw badRequest('Modo de sorteo inválido (ponderado | prioridad)');
  const cycle = await getCycle(cycleId);
  assertDrawable(cycle);
  const { eligible, excluded } = await evaluateResidents(cycle);
  const spots = await availableSpots(cycle.id);
  const order = drawOrder(eligible, mode);
  const { proposal, waitlist } = matchSpots(order, spots);
  return {
    cycle,
    mode,
    spots_available: spots.length,
    eligible_count: eligible.length,
    proposal: proposal.map((p, i) => ({
      position: i + 1,
      resident_id: p.resident_id,
      full_name: p.full_name,
      house: p.house,
      vehicle_id: p.vehicle?.id,
      plate: p.vehicle?.plate,
      parking_spot_id: p.spot.id,
      spot_code: p.spot.code,
      ipa: p.ipa,
      components: p.components,
    })),
    waitlist: waitlist.map((w) => ({
      resident_id: w.resident_id,
      full_name: w.full_name,
      house: w.house,
      ipa: w.ipa,
      components: w.components,
    })),
    excluded: excluded.map((x) => ({
      resident_id: x.resident_id,
      full_name: x.full_name,
      house: x.house,
      reasons: x.reasons,
    })),
  };
}

/**
 * Confirma un sorteo. Si se envía `proposal` (posiblemente modificada por el
 * administrador) se valida y se guarda tal cual; si no, se ejecuta el sorteo.
 * Debe llamarse dentro de una transacción (tx).
 */
export async function confirmDraw(tx, cycleId, { mode = 'ponderado', proposal } = {}) {
  const cycle = await getCycle(cycleId, tx);
  assertDrawable(cycle);
  await tx`SELECT pg_advisory_xact_lock(4242, ${cycle.id})`;
  const { eligible, excluded } = await evaluateResidents(cycle, tx);
  const spots = await availableSpots(cycle.id, tx);

  let final;
  let waitlist;
  if (Array.isArray(proposal) && proposal.length) {
    const eligibleById = new Map(eligible.map((e) => [e.resident_id, e]));
    const spotsById = new Map(spots.map((s) => [s.id, s]));
    const seenR = new Set();
    const seenS = new Set();
    final = proposal.map((p) => {
      const rid = Number(p.resident_id);
      const sid = Number(p.parking_spot_id);
      const e = eligibleById.get(rid);
      if (!e) throw badRequest(`El residente ${rid} no es elegible para este ciclo`);
      if (!spotsById.has(sid)) throw badRequest(`La celda ${sid} no está disponible en este ciclo`);
      if (seenR.has(rid) || seenS.has(sid)) throw badRequest('La propuesta tiene residentes o celdas repetidos');
      seenR.add(rid);
      seenS.add(sid);
      return { ...e, spot: spotsById.get(sid) };
    });
    waitlist = eligible.filter((e) => !seenR.has(e.resident_id));
  } else {
    const order = drawOrder(eligible, mode);
    ({ proposal: final, waitlist } = matchSpots(order, spots));
  }

  const inserted = [];
  for (const p of final) {
    if (!p.vehicle) continue;
    const [row] = await tx`
      INSERT INTO parking_assignment (cycle_id, resident_id, vehicle_id, parking_spot_id, method, ipa_score)
      VALUES (${cycle.id}, ${p.resident_id}, ${p.vehicle.id}, ${p.spot.id}, 'sorteo', ${p.ipa})
      RETURNING id`;
    inserted.push({
      assignment_id: row.id,
      resident_id: p.resident_id,
      full_name: p.full_name,
      house: p.house,
      plate: p.vehicle.plate,
      spot_code: p.spot.code,
      ipa: p.ipa,
    });
  }
  if (!cycle.draw_date) {
    await tx`UPDATE cycle SET draw_date = CURRENT_DATE WHERE id = ${cycle.id}`;
  }
  return { cycle, mode, assigned: inserted, waitlist, excluded_count: excluded.length };
}
