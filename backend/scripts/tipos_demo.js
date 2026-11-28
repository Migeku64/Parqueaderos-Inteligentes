// Propietarios y arrendatarios de demostración.
// Cerca de 3 de cada 10 casas están arrendadas (repartidas, no seguidas), como en un conjunto real.
// La misma regla se usa en seed.js y en el SQL para actualizar una base que ya tiene datos.
export function demoResidentType(houseNumber) {
  const n = Number(houseNumber) || 0;
  return [1, 4, 8].includes((n * 7) % 10) ? 'arrendatario' : 'propietario';
}
