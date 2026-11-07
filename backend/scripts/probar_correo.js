// Envía un correo de prueba para verificar la configuración de Brevo.
// Uso:  npm run correo:prueba -- su-correo@ejemplo.com
import { emailConfig, emailEnabled, renderEmail, sendEmail } from '../src/services/email.js';
import { sql } from '../src/db.js';

const to = process.argv[2];
if (!to) {
  console.error('Uso: npm run correo:prueba -- su-correo@ejemplo.com');
  process.exit(1);
}
if (!emailEnabled()) {
  console.error('El correo no está configurado. Defina BREVO_API_KEY y EMAIL_FROM en backend/.env (vea README).');
  process.exit(1);
}
const c = emailConfig();
const { html, text } = renderEmail({
  name: 'Residente',
  title: 'Correo de prueba del parqueadero',
  body: 'Si recibe este mensaje, las notificaciones por correo del sistema están funcionando correctamente.',
});
const r = await sendEmail({ to: [{ email: to }], subject: 'Correo de prueba del parqueadero', html, text });
if (r.ok) {
  console.log(`Correo enviado a ${c.redirectTo || to} desde ${c.from}. Revise la bandeja de entrada (y la carpeta de spam).`);
} else {
  console.error(`No se pudo enviar el correo (${r.status || 'sin respuesta'}): ${r.error}`);
  process.exitCode = 1;
}
await sql.end();
