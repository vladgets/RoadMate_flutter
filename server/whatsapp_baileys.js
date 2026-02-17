/**
 * WhatsApp auto-send via Baileys (unofficial WhatsApp Web API).
 *
 * Endpoints:
 *   GET  /whatsapp/status?client_id=xxx  — connection state + QR if pending
 *   POST /whatsapp/connect  { client_id } — initiate pairing
 *   POST /whatsapp/send     { client_id, phone, message } — send message
 *   POST /whatsapp/disconnect { client_id } — logout + delete credentials
 */

import QRCode from 'qrcode';
import pino from 'pino';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SESSION_ROOT = path.join(__dirname, 'wa_sessions');

// In-memory state per client_id.
const sessions = new Map();

const silentLogger = pino({ level: 'silent' });

// Lazy-load Baileys so import errors surface cleanly at connect time.
let _baileys = null;
async function getBaileys() {
  if (_baileys) return _baileys;
  try {
    _baileys = await import('@whiskeysockets/baileys');
    return _baileys;
  } catch (e) {
    throw new Error(`Failed to load Baileys: ${e.message}`);
  }
}

function sessionDir(clientId) {
  const dir = path.join(SESSION_ROOT, clientId);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

async function createSession(clientId) {
  // Tear down any existing socket cleanly.
  const prev = sessions.get(clientId);
  if (prev?.socket) {
    try { prev.socket.end(undefined); } catch (_) {}
  }

  const state = {
    socket: null,
    connected: false,
    connecting: true,   // explicit flag, not derived
    qrBase64: null,
    phone: null,
    lastError: null,
  };
  sessions.set(clientId, state);

  // Timeout: if no QR or connection after 40s, surface an error.
  const timeoutHandle = setTimeout(() => {
    if (state.connecting && !state.connected && !state.qrBase64) {
      state.connecting = false;
      state.lastError = 'Timed out waiting for WhatsApp QR. Check Render logs and retry.';
      console.error(`[WhatsApp] Timeout waiting for QR for client ${clientId}`);
    }
  }, 40_000);

  try {
    const baileys = await getBaileys();
    const makeWASocket = baileys.default ?? baileys.makeWASocket;
    const { useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion } = baileys;

    // Fetch the current WhatsApp Web version — required or the handshake hangs.
    const { version, isLatest } = await fetchLatestBaileysVersion();
    console.log(`[WhatsApp] Using WA version ${version.join('.')} (latest: ${isLatest})`);

    const dir = sessionDir(clientId);
    const { state: authState, saveCreds } = await useMultiFileAuthState(dir);

    const socket = makeWASocket({
      version,
      auth: authState,
      logger: silentLogger,
      printQRInTerminal: false,
      browser: ['RoadMate', 'Chrome', '120.0.0'],
    });

    state.socket = socket;

    socket.ev.on('creds.update', saveCreds);

    socket.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        clearTimeout(timeoutHandle);
        try {
          const dataUrl = await QRCode.toDataURL(qr, { margin: 1, width: 300 });
          state.qrBase64 = dataUrl.split(',')[1];
        } catch (e) {
          console.error('[WhatsApp] QR generation failed:', e.message);
          state.qrBase64 = null;
        }
        state.connected = false;
        state.connecting = false;
        state.lastError = null;
      }

      if (connection === 'open') {
        clearTimeout(timeoutHandle);
        state.connected = true;
        state.connecting = false;
        state.qrBase64 = null;
        state.lastError = null;
        state.phone = socket.user?.id?.split(':')[0] ?? null;
        console.log(`[WhatsApp] Client ${clientId} connected as ${state.phone}`);
      }

      if (connection === 'close') {
        state.connected = false;
        state.qrBase64 = null;

        const statusCode = lastDisconnect?.error?.output?.statusCode
          ?? lastDisconnect?.error?.output?.status;
        const loggedOut = statusCode === DisconnectReason.loggedOut
          || statusCode === 401;

        if (loggedOut) {
          console.log(`[WhatsApp] Client ${clientId} logged out.`);
          state.connecting = false;
          state.lastError = 'Logged out from WhatsApp. Please reconnect.';
          sessions.delete(clientId);
          try { fs.rmSync(sessionDir(clientId), { recursive: true, force: true }); } catch (_) {}
        } else {
          console.log(`[WhatsApp] Client ${clientId} disconnected (code ${statusCode}), reconnecting...`);
          state.connecting = true;
          setTimeout(() => createSession(clientId).catch((e) => {
            state.connecting = false;
            state.lastError = e.message;
          }), 3000);
        }
      }
    });

  } catch (e) {
    clearTimeout(timeoutHandle);
    console.error(`[WhatsApp] createSession failed for ${clientId}:`, e.message);
    state.connecting = false;
    state.lastError = e.message;
  }

  return state;
}

/** On server startup, restore sessions that have saved credentials. */
async function restoreSessions() {
  if (!fs.existsSync(SESSION_ROOT)) return;
  const entries = fs.readdirSync(SESSION_ROOT, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    console.log(`[WhatsApp] Restoring session for client ${entry.name}...`);
    createSession(entry.name).catch(console.error);
  }
}

export function registerWhatsAppBaileysRoutes(app) {
  restoreSessions().catch(console.error);

  // ── GET /whatsapp/status?client_id=xxx ──────────────────────────────────
  app.get('/whatsapp/status', (req, res) => {
    const clientId = req.query.client_id;
    if (!clientId) return res.status(400).json({ ok: false, error: 'Missing client_id' });

    const s = sessions.get(clientId);
    if (!s) {
      return res.json({ ok: true, connected: false, connecting: false,
        qrBase64: null, phone: null, lastError: null });
    }

    return res.json({
      ok: true,
      connected: s.connected,
      connecting: s.connecting,
      qrBase64: s.qrBase64 ?? null,
      phone: s.phone ?? null,
      lastError: s.lastError ?? null,
    });
  });

  // ── POST /whatsapp/connect ───────────────────────────────────────────────
  app.post('/whatsapp/connect', async (req, res) => {
    const { client_id } = req.body ?? {};
    if (!client_id) return res.status(400).json({ ok: false, error: 'Missing client_id' });

    const existing = sessions.get(client_id);
    if (existing?.connected) {
      return res.json({ ok: true, already_connected: true, phone: existing.phone });
    }

    createSession(client_id).catch(console.error);
    return res.json({ ok: true, message: 'Connecting — poll /whatsapp/status for QR.' });
  });

  // ── POST /whatsapp/send ──────────────────────────────────────────────────
  app.post('/whatsapp/send', async (req, res) => {
    const { client_id, phone, message } = req.body ?? {};
    if (!client_id || !phone || !message) {
      return res.status(400).json({ ok: false, error: 'Missing client_id, phone, or message' });
    }

    const s = sessions.get(client_id);
    if (!s?.connected) {
      return res.status(400).json({ ok: false,
        error: 'WhatsApp not connected. Open RoadMate settings to pair.' });
    }

    try {
      const digits = phone.replace(/[^0-9]/g, '');
      const jid = `${digits}@s.whatsapp.net`;
      await s.socket.sendMessage(jid, { text: message });
      console.log(`[WhatsApp] Sent to ${digits} for client ${client_id}`);
      return res.json({ ok: true, to: digits });
    } catch (e) {
      console.error(`[WhatsApp] Send error:`, e.message);
      return res.status(500).json({ ok: false, error: e.message });
    }
  });

  // ── POST /whatsapp/disconnect ────────────────────────────────────────────
  app.post('/whatsapp/disconnect', async (req, res) => {
    const { client_id } = req.body ?? {};
    if (!client_id) return res.status(400).json({ ok: false, error: 'Missing client_id' });

    const s = sessions.get(client_id);
    if (s?.socket) {
      try { await s.socket.logout(); } catch (_) {}
    }
    sessions.delete(client_id);
    try { fs.rmSync(sessionDir(client_id), { recursive: true, force: true }); } catch (_) {}

    console.log(`[WhatsApp] Client ${client_id} disconnected and cleared.`);
    return res.json({ ok: true });
  });
}
