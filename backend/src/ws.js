// Servidor WebSocket mínimo (RFC 6455) para notificar cambios en tiempo real.
// Conexión: ws://servidor:3000/ws?token=<JWT>
// Mensajes enviados al cliente: {"event":"spots"|"movement"|"assignments"|"notification", "data":{...}}
import crypto from 'node:crypto';
import { userFromToken } from './auth.js';

const clients = new Set();
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

function frame(payload, opcode = 0x1) {
  const data = Buffer.isBuffer(payload) ? payload : Buffer.from(payload);
  const len = data.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x80 | opcode, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, data]);
}

function parseFrames(client, chunk) {
  client.buffer = Buffer.concat([client.buffer, chunk]);
  while (client.buffer.length >= 2) {
    const b = client.buffer;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let offset = 2;
    if (len === 126) {
      if (b.length < 4) return;
      len = b.readUInt16BE(2);
      offset = 4;
    } else if (len === 127) {
      if (b.length < 10) return;
      len = Number(b.readBigUInt64BE(2));
      offset = 10;
    }
    if (len > 65536) return close(client);
    const maskLen = masked ? 4 : 0;
    if (b.length < offset + maskLen + len) return;
    const mask = masked ? b.subarray(offset, offset + 4) : null;
    const payload = Buffer.from(b.subarray(offset + maskLen, offset + maskLen + len));
    if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
    client.buffer = b.subarray(offset + maskLen + len);

    if (opcode === 0x8) return close(client); // close
    if (opcode === 0x9) client.socket.write(frame(payload, 0xa)); // ping -> pong
    // Los mensajes de texto del cliente se ignoran (solo "keep-alive").
  }
}

function close(client) {
  if (!clients.has(client)) return;
  clients.delete(client);
  try {
    client.socket.end(frame(Buffer.alloc(0), 0x8));
  } catch {
    /* ignorar */
  }
}

export function attachWebSocket(server) {
  server.on('upgrade', async (req, socket) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname !== '/ws' || (req.headers.upgrade || '').toLowerCase() !== 'websocket') {
        socket.destroy();
        return;
      }
      const user = await userFromToken(url.searchParams.get('token'));
      if (!user) {
        socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n');
        return;
      }
      const key = req.headers['sec-websocket-key'];
      const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
      socket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
          'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
          `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
      );
      socket.setNoDelay(true);
      const client = { socket, user, buffer: Buffer.alloc(0) };
      clients.add(client);
      socket.on('data', (c) => parseFrames(client, c));
      socket.on('close', () => clients.delete(client));
      socket.on('error', () => clients.delete(client));
      socket.write(frame(JSON.stringify({ event: 'hello', data: { user: user.username } })));
    } catch {
      socket.destroy();
    }
  });

  // Ping cada 30 s para mantener vivas las conexiones a través de proxies
  const timer = setInterval(() => {
    for (const c of clients) {
      try {
        c.socket.write(frame(Buffer.alloc(0), 0x9));
      } catch {
        clients.delete(c);
      }
    }
  }, 30_000);
  timer.unref();
}

/**
 * Envía un evento a los clientes conectados.
 * @param {string} event
 * @param {object} data
 * @param {{roles?: string[], userIds?: number[]}} [to]
 */
export function broadcast(event, data = {}, to = {}) {
  const msg = frame(JSON.stringify({ event, data }));
  for (const c of clients) {
    if (to.roles && !to.roles.includes(c.user.role)) continue;
    if (to.userIds && !to.userIds.includes(c.user.id)) continue;
    try {
      c.socket.write(msg);
    } catch {
      clients.delete(c);
    }
  }
}

export function closeAllWebSockets() {
  for (const c of [...clients]) close(c);
}
