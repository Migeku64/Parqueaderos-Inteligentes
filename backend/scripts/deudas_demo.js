// Deudas variadas para los residentes de demostración.
// Antes todos los que debían tenían exactamente $85.000. Aquí la deuda depende, como en un
// conjunto real, de la cuota de cada casa (según su coeficiente), de cuántas cuotas debe
// (de 1 a 14), del interés de mora y de si ya hizo algún abono. La mezcla es fija: siempre
// da el mismo resultado.
const MESES = [1, 1, 1, 2, 2, 2, 3, 3, 4, 5, 6, 8, 11, 14]; // la mayoría debe poco; pocos deben mucho

function mix(n) {
  let x = Math.imul(n + 17, 2654435761) >>> 0;
  x = (x ^ (x >>> 15)) >>> 0;
  x = Math.imul(x, 2246822519) >>> 0;
  return (x ^ (x >>> 13)) >>> 0;
}

/** Deuda de demostración del residente generado número i (en pesos, redondeada a $100). */
export function demoDebt(i) {
  // Cuota mensual entre $92.000 y $118.000 según el coeficiente de la casa
  const cuota = 92000 + (mix(i + 7) % 14) * 2000;
  const meses = MESES[mix(i) % MESES.length];
  // Interés de mora del 2 % mensual sobre cada cuota atrasada
  const interes = cuota * 0.02 * ((meses * (meses - 1)) / 2);
  // Uno de cada tres ya abonó una parte (entre $10.000 y $60.000)
  const abono = mix(i + 31) % 3 === 0 ? 10000 + (mix(i + 53) % 11) * 5000 : 0;
  return Math.max(10000, Math.round((cuota * meses + interes - abono) / 100) * 100);
}

/** La deuda que ponía la versión anterior a todos los que debían. */
export const OLD_DEMO_DEBT = 85000;
