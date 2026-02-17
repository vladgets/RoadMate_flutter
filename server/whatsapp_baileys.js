/**
 * WhatsApp auto-send via Baileys (unofficial WhatsApp Web API).
 *
 * Each app install (client_id) gets its own WhatsApp session.
 * Sessions are persisted to disk (wa_sessions/{client_id}/) so they
 * survive server restarts. Add a Render Persistent Disk mounted at
 * the app directory to survive redeploys too.
 *
 * Endpoints:
 *   GET  /whatsapp/status?client_id=xxx  — connection state + QR if pending
 *   POST /whatsapp/connect  { client_id } — initiate pairing
 *   POST /whatsapp/send     { client_id, phone, message } — send message
 *   POST /whatsapp/disconnect { client_id } — logout + delete credentials
 */

import makeWASocket, {
  useMultiFileAuthState,
  DisconnectReason,
} from '@whiskeysockets/baileys';
import QRCode from 'qrcode';
import pino from 'pino';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SESSION_ROOT = path.join(__dirname, 'wa_sessions');

// In-memory state per client_id.
// { socket, connected, qrBase64, phone, reconnecting }
const sessions = new Map();

const silentLogger = pino({ level: 'silent' });

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
    qrBase64: null,
    phone: null,
    reconnecting: false,
  };
  sessions.set(clientId, state);

  const dir = sessionDir(clientId);
  const { state: authState, saveCreds } = await useMultiFileAuthState(dir);

  const socket = makeWASocket({
    auth: authState,
    logger: silentLogger,
    printQRInTerminal: false,
    browser: ['RoadMate', 'Safari', '1.0'],
  });

  state.socket = socket;

  socket.ev.on('creds.update', saveCreds);

  socket.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update;

    // New QR available — convert to base64 PNG for the app to display.
    if (qr) {
      try {
        const dataUrl = await QRCode.toDataURL(qr, { margin: 1, width: 300 });
        state.qrBase64 = dataUrl.split(',')[1]; // strip "data:image/png;base64,"
      } catch (_) {
        state.qrBase64 = null;
      }
      state.connected = false;
    }

    if (connection === 'open') {
      state.connected = true;
      state.qrBase64 = null;
      state.reconnecting = false;
      // Extract phone number from the JID (format: "15551234567:42@s.whatsapp.net")
      state.phone = socket.user?.id?.split(':')[0] ?? null;
      console.log(`[WhatsApp] Client ${clientId} connected as ${state.phone}`);
    }

    if (connection === 'close') {
      state.connected = false;
      state.qrBase64 = null;

      const statusCode = lastDisconnect?.error?.output?.statusCode;
      const loggedOut = statusCode === DisconnectReason.loggedOut;

      if (loggedOut) {
        // User logged out from phone — clear everything.
        console.log(`[WhatsApp] Client ${clientId} logged out.`);
        sessions.delete(clientId);
        try { fs.rmSync(sessionDir(clientId), { recursive: true, force: true }); } catch (_) {}
      } else {
        // Network drop / server issue — auto-reconnect.
        console.log(`[WhatsApp] Client ${clientId} disconnected (code ${statusCode}), reconnecting...`);
        state.reconnecting = true;
        setTimeout(() => createSession(clientId).catch(console.error), 3000);
      }
    }
  });

  return state;
}

/** On server startup, restore any sessions that have saved credentials. */
async function restoreSessions() {
  if (!fs.existsSync(SESSION_ROOT)) return;
  const entries = fs.readdirSync(SESSION_ROOT, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const clientId = entry.name;
    console.log(`[WhatsApp] Restoring session for client ${clientId}...`);
    createSession(clientId).catch(console.error);
  }
}

export function registerWhatsAppBaileysRoutes(app) {
  // Restore persisted sessions on startup.
  restoreSessions().catch(console.error);

  // ── GET /whatsapp/status?client_id=xxx ──────────────────────────────────
  app.get('/whatsapp/status', (req, res) => {
    const clientId = req.query.client_id;
    if (!clientId) return res.status(400).json({ ok: false, error: 'Missing client_id' });

    const s = sessions.get(clientId);
    if (!s) {
      return res.json({ ok: true, connected: false, qrBase64: null, phone: null, connecting: false });
    }

    return res.json({
      ok: true,
      connected: s.connected,
      qrBase64: s.qrBase64 ?? null,
      phone: s.phone ?? null,
      connecting: !s.connected && !s.qrBase64 && !s.reconnecting,
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

    // Start session asynchronously — return immediately so the app can start polling.
    createSession(client_id).catch(console.error);

    return res.json({ ok: true, message: 'Connecting, poll /whatsapp/status for QR.' });
  });

  // ── POST /whatsapp/send ──────────────────────────────────────────────────
  app.post('/whatsapp/send', async (req, res) => {
    const { client_id, phone, message } = req.body ?? {};
    if (!client_id || !phone || !message) {
      return res.status(400).json({ ok: false, error: 'Missing client_id, phone, or message' });
    }

    const s = sessions.get(client_id);
    if (!s?.connected) {
      return res.status(400).json({ ok: false, error: 'WhatsApp not connected. Open RoadMate settings to pair.' });
    }

    try {
      // Strip everything except digits (keep international format).
      const digits = phone.replace(/[^0-9]/g, '');
      const jid = `${digits}@s.whatsapp.net`;
      await s.socket.sendMessage(jid, { text: message });
      console.log(`[WhatsApp] Sent message to ${digits} for client ${client_id}`);
      return res.json({ ok: true, to: digits });
    } catch (e) {
      console.error(`[WhatsApp] Send error: ${e}`);
      return res.status(500).json({ ok: false, error: String(e) });
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

    console.log(`[WhatsApp] Client ${client_id} disconnected and credentials cleared.`);
    return res.json({ ok: true });
  });
}
