// Notificaciones por correo electrónico (RF13) usando la API HTTPS de Brevo.
//
// Se usa una API por HTTPS (y no SMTP) porque el plan gratuito de Render bloquea
// los puertos de correo 25, 465 y 587. Brevo permite 300 correos diarios gratis.
//
// Configuración (.env):
//   BREVO_API_KEY      clave de la API de Brevo (si está vacía, no se envían correos)
//   EMAIL_FROM         remitente verificado en Brevo (ej. parqueadero.nuevacastilla@gmail.com)
//   EMAIL_FROM_NAME    nombre del remitente
//   EMAIL_ADMINS       correos de la administración, separados por coma
//   EMAIL_REDIRECT_TO  (opcional) envía TODOS los correos a esta dirección; útil para
//                      demostraciones con los datos de prueba
import { sql } from '../db.js';

const env = process.env;

export function emailConfig() {
  return {
    apiKey: env.BREVO_API_KEY || '',
    apiUrl: env.BREVO_API_URL || 'https://api.brevo.com/v3/smtp/email',
    from: env.EMAIL_FROM || '',
    fromName: env.EMAIL_FROM_NAME || 'Parqueadero Comunitario Nueva Castilla',
    admins: (env.EMAIL_ADMINS || '').split(',').map((s) => s.trim()).filter(Boolean),
    redirectTo: (env.EMAIL_REDIRECT_TO || '').trim(),
    delayMs: Number(env.EMAIL_DELAY_MS ?? 1500),
  };
}

export function emailEnabled() {
  const c = emailConfig();
  return Boolean(c.apiKey && c.from);
}

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export function renderEmail({ name, title, body }) {
  const greeting = name ? `Hola, ${name}:` : 'Hola:';
  const text = `${greeting}\n\n${title}\n\n${body || ''}\n\nIngrese a la aplicación del parqueadero para ver el detalle.\n\n`
    + 'Este es un mensaje automático del Sistema de Gestión de Parqueaderos Comunitarios - Conjunto Residencial Nueva Castilla Etapa 3. Por favor no lo responda.';
  const html = `<!doctype html><html lang="es"><body style="margin:0;padding:0;background:#f3f5f9;font-family:Arial,Helvetica,sans-serif;color:#1f2933">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f5f9;padding:24px 0"><tr><td align="center">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#ffffff;border-radius:8px;overflow:hidden">
<tr><td style="background:#2f5597;color:#ffffff;padding:18px 24px;font-size:16px;font-weight:bold">Parqueadero Comunitario &middot; Nueva Castilla Etapa 3</td></tr>
<tr><td style="padding:24px">
<p style="margin:0 0 12px">${esc(greeting)}</p>
<h2 style="margin:0 0 12px;font-size:20px;color:#1f3864">${esc(title)}</h2>
<p style="margin:0 0 20px;line-height:1.5">${esc(body).replace(/\n/g, '<br>')}</p>
<p style="margin:0;color:#52606d;font-size:14px">Ingrese a la aplicación del parqueadero para ver el detalle.</p>
</td></tr>
<tr><td style="padding:14px 24px;background:#f8f9fb;color:#7b8794;font-size:12px;line-height:1.4">Mensaje automático del Sistema de Gestión de Parqueaderos Comunitarios. Por favor no responda este correo.</td></tr>
</table></td></tr></table></body></html>`;
  return { html, text };
}

/** Envía un correo con la API de Brevo. Devuelve { ok, status, error }. */
export async function sendEmail({ to, subject, html, text }) {
  const c = emailConfig();
  if (!c.apiKey || !c.from) return { ok: false, error: 'Correo no configurado (BREVO_API_KEY / EMAIL_FROM)' };
  let recipients = to.filter((r) => r && r.email);
  if (c.redirectTo) {
    subject = `[Para: ${recipients.map((r) => r.email).join(', ')}] ${subject}`;
    recipients = [{ email: c.redirectTo }];
  }
  if (!recipients.length) return { ok: false, error: 'Sin destinatarios' };
  try {
    const res = await fetch(c.apiUrl, {
      method: 'POST',
      headers: { 'api-key': c.apiKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        sender: { email: c.from, name: c.fromName },
        to: recipients,
        subject,
        htmlContent: html,
        textContent: text,
      }),
      signal: AbortSignal.timeout(15000),
    });
    if (res.ok) return { ok: true, status: res.status };
    return { ok: false, status: res.status, error: (await res.text()).slice(0, 300) };
  } catch (err) {
    return { ok: false, error: err.message || String(err) };
  }
}

/**
 * Programa el envío por correo de notificaciones recién creadas.
 * Se ejecuta unos instantes después para que la transacción que las creó ya esté confirmada;
 * si esa transacción se deshizo, las notificaciones no existen y no se envía nada.
 */
export function queueNotificationEmails(notificationIds) {
  if (!notificationIds.length || !emailEnabled()) return;
  const t = setTimeout(() => {
    sendNotificationEmails(notificationIds).catch((err) => console.error('[correo] error', err));
  }, emailConfig().delayMs);
  t.unref?.();
}

export async function sendNotificationEmails(notificationIds) {
  const c = emailConfig();
  const rows = await sql`
    SELECT n.id, n.titulo, n.cuerpo, n.rol_destino, cu.rol, r.correo, r.nombre_completo
    FROM notificacion n
    JOIN cuenta_usuario cu ON cu.id = n.cuenta_usuario_id
    LEFT JOIN residente r ON r.id = cu.residente_id
    WHERE n.id IN ${sql(notificationIds)} AND n.correo_enviado_en IS NULL`;
  const sentIds = [];
  // Residentes: un correo personal a cada uno
  for (const n of rows.filter((x) => x.role === 'residente' && x.email)) {
    const { html, text } = renderEmail({ name: n.full_name, title: n.title, body: n.body });
    const r = await sendEmail({ to: [{ email: n.email, name: n.full_name }], subject: n.title, html, text });
    if (r.ok) sentIds.push(n.id);
    else console.error(`[correo] no se pudo enviar a ${n.email}: ${r.error}`);
  }
  // Administración: un solo correo por notificación, a las direcciones de EMAIL_ADMINS
  const adminRows = rows.filter((x) => x.role === 'admin');
  if (adminRows.length && c.admins.length) {
    const groups = new Map();
    for (const n of adminRows) {
      const k = `${n.title}\n${n.body}`;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(n);
    }
    for (const list of groups.values()) {
      const n = list[0];
      const { html, text } = renderEmail({ name: 'Administración', title: n.title, body: n.body });
      const r = await sendEmail({ to: c.admins.map((email) => ({ email })), subject: n.title, html, text });
      if (r.ok) sentIds.push(...list.map((x) => x.id));
      else console.error(`[correo] no se pudo enviar a la administración: ${r.error}`);
    }
  }
  if (sentIds.length) await sql`UPDATE notificacion SET correo_enviado_en = now() WHERE id IN ${sql(sentIds)}`;
  return sentIds.length;
}
