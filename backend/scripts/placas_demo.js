// Placas y vehículos variados para los residentes de demostración.
// Antes todas las placas salían de una fórmula que empezaba siempre por «G» (GBS360, GHF165…).
// Aquí se generan placas con el formato colombiano —carro: ABC123, moto: ABC12D— usando una
// mezcla pseudoaleatoria fija: siempre da el mismo resultado y no se repiten.

const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const OLD_LETTERS = 'BCDFGHJKLMNPRSTVWXYZ';

const CARS = [
  ['CHEVROLET', 'SPARK GT'], ['CHEVROLET', 'ONIX'], ['CHEVROLET', 'TRACKER'], ['CHEVROLET', 'SAIL'],
  ['RENAULT', 'SANDERO'], ['RENAULT', 'LOGAN'], ['RENAULT', 'STEPWAY'], ['RENAULT', 'KWID'],
  ['MAZDA', '2'], ['MAZDA', '3'], ['MAZDA', 'CX-30'], ['KIA', 'PICANTO'], ['KIA', 'RIO'],
  ['KIA', 'SPORTAGE'], ['TOYOTA', 'COROLLA'], ['TOYOTA', 'YARIS'], ['SUZUKI', 'SWIFT'],
  ['NISSAN', 'MARCH'], ['NISSAN', 'VERSA'], ['VOLKSWAGEN', 'GOL'], ['HYUNDAI', 'ACCENT'],
  ['FORD', 'FIESTA'], ['BYD', 'DOLPHIN'], ['RENAULT', 'DUSTER'],
];
const SUVS = [
  ['TOYOTA', 'FORTUNER'], ['HYUNDAI', 'TUCSON'], ['NISSAN', 'X-TRAIL'], ['MAZDA', 'CX-5'],
  ['FORD', 'ESCAPE'], ['CHEVROLET', 'CAPTIVA'], ['KIA', 'SORENTO'], ['TOYOTA', 'PRADO'],
];
const MOTOS = [
  ['YAMAHA', 'NMAX'], ['YAMAHA', 'FZ 2.0'], ['YAMAHA', 'XTZ 150'], ['HONDA', 'CB 160F'],
  ['HONDA', 'XR 150L'], ['BAJAJ', 'PULSAR NS 200'], ['BAJAJ', 'BOXER CT 100'], ['AKT', 'NKD 125'],
  ['SUZUKI', 'GIXXER 150'], ['TVS', 'APACHE RTR 160'], ['KTM', 'DUKE 200'], ['AUTECO', 'VICTORY ONE'],
];
const COLORS = ['Blanco', 'Gris', 'Negro', 'Plata', 'Rojo', 'Azul', 'Beige', 'Verde', 'Vinotinto', 'Naranja'];

// Mezcla entera simple y fija (no usa Math.random para que el resultado no cambie)
function mix(n) {
  let x = Math.imul(n + 1, 2654435761) >>> 0;
  x = (x ^ (x >>> 16)) >>> 0;
  x = Math.imul(x, 2246822519) >>> 0;
  x = (x ^ (x >>> 13)) >>> 0;
  x = Math.imul(x, 3266489917) >>> 0;
  return (x ^ (x >>> 16)) >>> 0;
}

const pick = (list, seed) => list[mix(seed) % list.length];

/** Tipo del vehículo de demostración número i (igual que antes: uno de cada seis es moto). */
export function demoVehicleType(i) {
  if (i % 6 === 0) return 'moto';
  return mix(i + 9000) % 7 === 0 ? 'camioneta' : 'carro';
}

/** Placa candidata número `attempt` para el vehículo i. */
function candidate(i, type, attempt) {
  const s = i * 31 + attempt * 7777;
  const l = (k) => LETTERS[mix(s + k * 101) % LETTERS.length];
  const d = (k) => String(mix(s + k * 211 + 50000) % 10);
  if (type === 'moto') return l(1) + l(2) + l(3) + d(1) + d(2) + l(4);
  const digits = d(1) + d(2) + d(3);
  return l(1) + l(2) + l(3) + (digits === '000' ? '001' : digits);
}

/**
 * Placa de demostración del vehículo i. `taken` es el conjunto de placas ya usadas;
 * la placa elegida se agrega a él, así nunca se repite.
 */
export function demoPlate(i, type, taken) {
  for (let attempt = 0; ; attempt++) {
    const p = candidate(i, type, attempt);
    if (!taken.has(p)) {
      taken.add(p);
      return p;
    }
  }
}

/** Marca, modelo (con año) y color del vehículo de demostración i. */
export function demoVehicleInfo(i, type) {
  const list = type === 'moto' ? MOTOS : type === 'camioneta' ? SUVS : CARS;
  const [brand, model] = pick(list, i + 3000);
  const year = 2012 + (mix(i + 4000) % 14); // 2012 a 2025
  return { brand, model: `${model} ${year}`, color: pick(COLORS, i + 5000) };
}

/** La placa que generaba la fórmula anterior (todas empezaban por G). */
export function oldDemoPlate(i) {
  return 'G' + OLD_LETTERS[i % 20] + OLD_LETTERS[Math.floor(i / 20) % 20] + String(100 + i);
}
