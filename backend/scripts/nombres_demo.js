// Nombres variados para los residentes de demostración (casas sin residente fijo).
// Antes el nombre salía de una fórmula que repetía mucho «García»; aquí nombre y apellidos
// se eligen por separado con una mezcla pseudoaleatoria fija, así siempre da el mismo resultado.

const FIRST = [
  'Ana', 'Luis', 'Paula', 'Jorge', 'Daniela', 'Óscar', 'Carolina', 'Mateo', 'Juliana', 'Santiago',
  'Lina', 'Ricardo', 'Sara', 'Andrés', 'Valeria', 'Tomás', 'Mariana', 'Sebastián', 'Gabriela', 'Nicolás',
  'Isabella', 'Alejandro', 'Camila', 'David', 'Manuela', 'Esteban', 'Natalia', 'Javier', 'Laura', 'Cristian',
  'Diana', 'Fernando', 'Angélica', 'Hugo', 'Marcela', 'Iván', 'Lorena', 'Mauricio', 'Paola', 'Germán',
];

const LAST = [
  'García', 'Martínez', 'Sánchez', 'Díaz', 'Ruiz', 'Jiménez', 'Ortiz', 'Silva', 'Mendoza', 'Rincón',
  'Castro', 'Vargas', 'Rojas', 'Rodríguez', 'Gómez', 'López', 'Hernández', 'Pérez', 'Moreno', 'Torres',
  'Ramírez', 'Romero', 'Suárez', 'Cárdenas', 'Herrera', 'Medina', 'Aguilar', 'Pineda', 'Guzmán', 'Reyes',
  'Salazar', 'Cortés', 'Ospina', 'Quintero', 'Parra', 'Bermúdez', 'Acosta', 'Patiño', 'Zapata', 'Valencia',
];

// Mezcla entera simple y fija (no usa Math.random para que el resultado no cambie)
function mix(n) {
  let x = (n + 1) * 2654435761;
  x = (x ^ (x >>> 15)) >>> 0;
  x = Math.imul(x, 2246822519) >>> 0;
  return (x ^ (x >>> 13)) >>> 0;
}

/** Nombre de demostración número i (0, 1, 2…). */
export function demoName(i) {
  const f = FIRST[mix(i) % FIRST.length];
  const a = LAST[mix(i + 1000) % LAST.length];
  let b = LAST[mix(i + 2000) % LAST.length];
  if (b === a) b = LAST[(mix(i + 2000) + 7) % LAST.length];
  return `${f} ${a} ${b}`;
}

/** Nombre que producía la versión anterior de seed.js (para reconocer los que no se han editado). */
export function oldDemoName(i) {
  const first = ['Ana', 'Luis', 'Paula', 'Jorge', 'Daniela', 'Óscar', 'Carolina', 'Mateo', 'Juliana', 'Santiago', 'Lina', 'Ricardo', 'Sara', 'Andrés', 'Valeria', 'Tomás'];
  const last = ['García', 'Martínez', 'Sánchez', 'Díaz', 'Ruiz', 'Jiménez', 'Ortiz', 'Silva', 'Mendoza', 'Rincón', 'Castro', 'Vargas', 'Rojas'];
  return `${first[i % first.length]} ${last[(i * 7) % last.length]} ${last[(i * 3 + 1) % last.length]}`;
}
