import postgres from 'postgres';
import { config } from './config.js';

export const sql = postgres(config.databaseUrl, {
  max: 10,
  ssl: config.databaseSsl ? 'require' : false,
  onnotice: () => {},
  // Devuelve DATE como texto 'YYYY-MM-DD' (evita corrimientos de zona horaria)
  types: {
    date: {
      to: 1082,
      from: [1082],
      serialize: (x) => (x instanceof Date ? x.toISOString().slice(0, 10) : x),
      parse: (x) => x,
    },
  },
});

/** Convierte NUMERIC/BIGINT (que llegan como texto) a número. */
export function num(v) {
  return v === null || v === undefined ? v : Number(v);
}
