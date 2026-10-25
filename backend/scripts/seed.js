// Datos de demostración: 300 casas (1 a 300) con un residente cada una, 50 celdas, usuarios y 3 ciclos.
//   Administradores: mpinilla, acardona, jmontoya y admin   (clave: admin123)
//   Guarda:          guarda                                 (clave: guarda123)
//   Residentes:      casa + número de casa, ej. casa150     (clave: residente123)
import { sql } from '../src/db.js';
import { hashPassword } from '../src/auth.js';
import { confirmDraw } from '../src/services/draw.js';

function isoDate(d) {
  return d.toISOString().slice(0, 10);
}
function addMonths(d, m) {
  const x = new Date(d);
  x.setUTCMonth(x.getUTCMonth() + m);
  return x;
}

const TOTAL_HOUSES = 300;

const RESIDENTS = [
  ['Miguel Ángel Pinilla', '1012345678', '', '150', 'JEEP', 'WRANGLER 2025', 'Rojo', 'ABC123', 'carro', 0, 1, false],
  ['Ariadna Cardona', '1023456789', '', '201', 'MAZDA', '3 2022', 'Gris', 'XYZ789', 'carro', 0, 0, false],
  ['Julián Montoya', '1034567890', '', '205', 'RENAULT', 'LOGAN 2019', 'Blanco', 'JKL456', 'carro', 0, 2, false],
  ['Juan Pérez', '12345678', '', '101', 'CHEVROLET', 'SPARK 2018', 'Azul', 'BCD234', 'carro', 0, 0, false],
  ['María Gómez', '87654321', '', '102', 'KIA', 'PICANTO 2021', 'Negro', 'EFG567', 'carro', 150000, 0, false],
  ['Carlos López', '111222333', '', '103', null, null, null, null, null, 0, 0, false],
  ['Laura Rodríguez', '52111222', '', '204', 'TOYOTA', 'COROLLA 2020', 'Plata', 'HIJ890', 'carro', 0, 1, true],
  ['Andrés Castro', '79123456', '', '202', 'YAMAHA', 'NMAX 2023', 'Negro', 'KLM12F', 'moto', 0, 0, false],
  ['Sofía Ramírez', '1045678901', '', '45', 'NISSAN', 'MARCH 2017', 'Rojo', 'NOP345', 'carro', 0, 0, false],
  ['Diego Herrera', '80234567', '', '78', 'FORD', 'ESCAPE 2019', 'Blanco', 'QRS678', 'camioneta', 0, 3, false],
  ['Valentina Torres', '1056789012', '', '12', 'SUZUKI', 'SWIFT 2022', 'Azul', 'TUV901', 'carro', 0, 0, false],
  ['Camilo Vargas', '1067890123', '', '260', 'HYUNDAI', 'TUCSON 2021', 'Gris', 'WXY234', 'camioneta', 0, 0, false],
  ['Natalia Moreno', '1078901234', '', '275', 'VOLKSWAGEN', 'GOL 2016', 'Blanco', 'ZAB567', 'carro', 0, 1, false],
  ['Felipe Rojas', '1089012345', '', '299', 'CHEVROLET', 'ONIX 2023', 'Negro', 'CDE890', 'carro', 0, 0, false],
];

async function main() {
  const [{ count }] = await sql`SELECT count(*)::int AS count FROM user_account`;
  if (count > 0 && !process.argv.includes('--force')) {
    console.log('La base ya tiene datos. Use "npm run db:reset" para reiniciarla con datos de demostración.');
    return;
  }

  const residentPw = await hashPassword('residente123');
  const now = new Date();
  // Residentes registrados hace 14 meses (para que tengan tiempo de espera acumulado)
  const createdAt = addMonths(now, -14);

  await sql.begin(async (tx) => {
    // 50 celdas: D01..D50; D01 y D02 para personas con discapacidad
    const spots = Array.from({ length: 50 }, (_, i) => ({
      code: `D${String(i + 1).padStart(2, '0')}`,
      is_disabled_spot: i < 2,
    }));
    await tx`INSERT INTO parking_spot ${tx(spots)}`;

    for (const [name, doc, block, number, brand, model, color, plate, type, debt, score, disability] of RESIDENTS) {
      const [h] = await tx`INSERT INTO house (block, number) VALUES ('', ${number})
                           ON CONFLICT (block, number) DO UPDATE SET number = EXCLUDED.number RETURNING id`;
      const [r] = await tx`
        INSERT INTO resident (house_id, full_name, document_number, phone, email, debt, admin_score, has_disability, created_at)
        VALUES (${h.id}, ${name}, ${doc}, ${'3' + doc.slice(-9).padStart(9, '0')},
                ${name.split(' ')[0].toLowerCase() + '@correo.com'}, ${debt}, ${score}, ${disability}, ${createdAt})
        RETURNING id`;
      if (plate) {
        await tx`INSERT INTO vehicle (resident_id, plate, type, brand, model, color)
                 VALUES (${r.id}, ${plate}, ${type}, ${brand}, ${model}, ${color})`;
      }
      const username = 'casa' + number;
      await tx`INSERT INTO user_account (username, full_name, password_hash, role, resident_id)
               VALUES (${username}, ${name}, ${residentPw}, 'residente', ${r.id})`;
    }

    // Un residente por cada una de las demás casas (1 a 300): hay mucha más demanda que celdas
    const first = ['Ana', 'Luis', 'Paula', 'Jorge', 'Daniela', 'Óscar', 'Carolina', 'Mateo', 'Juliana', 'Santiago', 'Lina', 'Ricardo', 'Sara', 'Andrés', 'Valeria', 'Tomás'];
    const last = ['García', 'Martínez', 'Sánchez', 'Díaz', 'Ruiz', 'Jiménez', 'Ortiz', 'Silva', 'Mendoza', 'Rincón', 'Castro', 'Vargas', 'Rojas'];
    const letters = 'BCDFGHJKLMNPRSTVWXYZ';
    const usedHouses = new Set(RESIDENTS.map((r) => r[3]));
    let i = 0;
    for (let n = 1; n <= TOTAL_HOUSES; n++) {
      const number = String(n);
      if (usedHouses.has(number)) continue;
      const name = `${first[i % first.length]} ${last[(i * 7) % last.length]} ${last[(i * 3 + 1) % last.length]}`;
      const [h] = await tx`INSERT INTO house (block, number) VALUES ('', ${number})
                           ON CONFLICT (block, number) DO UPDATE SET number = EXCLUDED.number RETURNING id`;
      const doc = String(1100000000 + i * 7919);
      const [r] = await tx`
        INSERT INTO resident (house_id, full_name, document_number, phone, debt, admin_score, created_at)
        VALUES (${h.id}, ${name}, ${doc}, ${'31' + String(20000000 + i * 131).padStart(8, '0')},
                ${i % 8 === 0 ? 85000 : 0}, ${i % 13 === 0 ? 1 : 0}, ${createdAt}) RETURNING id`;
      if (i % 5 !== 4) {
        const plate = 'G' + letters[i % 20] + letters[Math.floor(i / 20) % 20] + String(100 + i);
        await tx`INSERT INTO vehicle (resident_id, plate, type) VALUES (${r.id}, ${plate}, ${i % 6 === 0 ? 'moto' : 'carro'})`;
      }
      await tx`INSERT INTO user_account (username, full_name, password_hash, role, resident_id)
               VALUES (${'casa' + number}, ${name}, ${residentPw}, 'residente', ${r.id})`;
      i++;
    }

    const adminPw = await hashPassword('admin123');
    await tx`INSERT INTO user_account (username, full_name, password_hash, role)
             VALUES ('mpinilla', 'Miguel Ángel Pinilla Báez', ${adminPw}, 'admin'),
                    ('acardona', 'Ariadna Cardona Martínez', ${adminPw}, 'admin'),
                    ('jmontoya', 'Julián Mauricio Montoya Rodríguez', ${adminPw}, 'admin'),
                    ('admin', 'Administración Nueva Castilla', ${adminPw}, 'admin'),
                    ('guarda', 'Guarda de seguridad', ${await hashPassword('guarda123')}, 'guarda')`;

    // Ciclo anterior (cerrado) y ciclo actual (activo), de 4 meses cada uno
    const prevStart = addMonths(now, -6);
    const prevEnd = addMonths(prevStart, 4);
    const curStart = prevEnd;
    const curEnd = addMonths(curStart, 4);
    const nextEnd = addMonths(curEnd, 4);

    const [prev] = await tx`INSERT INTO cycle (name, start_date, end_date, draw_date, status)
      VALUES (${'Ciclo ' + isoDate(prevStart).slice(0, 7)}, ${isoDate(prevStart)}, ${isoDate(prevEnd)}, ${isoDate(addMonths(prevStart, 0))}, 'planeado') RETURNING id`;
    // Tres residentes usaron el parqueadero en el ciclo anterior
    const prevSpots = await tx`SELECT id FROM parking_spot WHERE NOT is_disabled_spot ORDER BY code LIMIT 3`;
    const prevResidents = await tx`
      SELECT r.id AS rid, v.id AS vid FROM resident r JOIN vehicle v ON v.resident_id = r.id
      WHERE r.document_number IN ('1034567890','80234567','1078901234') ORDER BY r.id`;
    for (let i = 0; i < prevResidents.length; i++) {
      await tx`INSERT INTO parking_assignment (cycle_id, resident_id, vehicle_id, parking_spot_id, method, status, released_at)
               VALUES (${prev.id}, ${prevResidents[i].rid}, ${prevResidents[i].vid}, ${prevSpots[i].id}, 'sorteo', 'finalizada', ${prevEnd})`;
    }
    await tx`UPDATE cycle SET status = 'cerrado' WHERE id = ${prev.id}`;

    const [cur] = await tx`INSERT INTO cycle (name, start_date, end_date, draw_date)
      VALUES (${'Ciclo ' + isoDate(curStart).slice(0, 7)}, ${isoDate(curStart)}, ${isoDate(curEnd)}, ${isoDate(curStart)}) RETURNING id`;
    await confirmDraw(tx, cur.id, { mode: 'prioridad' });
    await tx`UPDATE cycle SET status = 'activo' WHERE id = ${cur.id}`;

    // Próximo ciclo planeado (para mostrar "próximo sorteo")
    await tx`INSERT INTO cycle (name, start_date, end_date, draw_date)
      VALUES (${'Ciclo ' + isoDate(curEnd).slice(0, 7)}, ${isoDate(curEnd)}, ${isoDate(nextEnd)}, ${isoDate(addMonths(curEnd, 0))})`;
    await tx`UPDATE cycle SET draw_date = (start_date - 7) WHERE status = 'planeado'`;

    // Algunos movimientos de ejemplo: los asignados que están dentro del conjunto
    const inside = await tx`
      SELECT pa.id, pa.parking_spot_id, v.id AS vid, v.plate FROM parking_assignment pa
      JOIN vehicle v ON v.id = pa.vehicle_id WHERE pa.cycle_id = ${cur.id} AND pa.status = 'vigente' LIMIT 6`;
    const guard = (await tx`SELECT id FROM user_account WHERE username = 'guarda'`)[0].id;
    for (const m of inside) {
      await tx`INSERT INTO vehicle_movement (plate, vehicle_id, parking_spot_id, assignment_id, type, authorized, recorded_by, recorded_at)
               VALUES (${m.plate}, ${m.vid}, ${m.parking_spot_id}, ${m.id}, 'entrada', TRUE, ${guard}, now() - interval '3 hours')`;
      await tx`UPDATE parking_spot SET is_occupied = TRUE WHERE id = ${m.parking_spot_id}`;
    }
  });

  const [{ n }] = await sql`SELECT count(*)::int AS n FROM resident`;
  console.log(`Datos de demostración creados: ${n} residentes (casas 1 a ${TOTAL_HOUSES}), 50 celdas, 3 ciclos.`);
  console.log('Usuarios de prueba:');
  console.log('  Administradores: mpinilla, acardona, jmontoya, admin   clave admin123');
  console.log('  Guarda:          guarda                                clave guarda123');
  console.log('  Residentes:      casa1 ... casa300 (ej. casa150)      clave residente123');
}

try {
  await main();
} catch (err) {
  console.error('Error creando datos de demostración:', err);
  process.exitCode = 1;
} finally {
  await sql.end();
}
