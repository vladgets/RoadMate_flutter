import fs from "fs";
import { google } from "googleapis";

const SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"];
const TOKEN_DIR = process.env.GOOGLE_TOKEN_DIR || "/data/gmail_tokens";

// GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, BASE_URL
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const BASE_URL = process.env.BASE_URL; // e.g. https://roadmate-flutter.onrender.com
const REDIRECT_URI = BASE_URL ? `${BASE_URL}/oauth/google/callback` : null;

function ensureTokenDir() {
  if (!fs.existsSync(TOKEN_DIR)) {
    fs.mkdirSync(TOKEN_DIR, { recursive: true });
  }
}

function sanitizeClientId(v) {
  if (typeof v !== "string") return null;
  const cid = v.trim();
  if (!cid) return null;
  // Allow only safe filename characters
  if (!/^[a-zA-Z0-9_-]{4,80}$/.test(cid)) return null;
  return cid;
}

function getClientIdFromReq(req) {
  return (
    sanitizeClientId(req.get("X-Client-Id")) ||
    sanitizeClientId(req.query.client_id) ||
    sanitizeClientId(req.body?.client_id)
  );
}

function tokenPathFor(clientId) {
  ensureTokenDir();
  return `${TOKEN_DIR}/${clientId}.json`;
}

// REQUIRED env vars for production (don't hardcode these):
function assertConfig() {
  const missing = [];
  if (!GOOGLE_CLIENT_ID) missing.push("GOOGLE_CLIENT_ID");
  if (!GOOGLE_CLIENT_SECRET) missing.push("GOOGLE_CLIENT_SECRET");
  if (!BASE_URL) missing.push("BASE_URL");
  if (missing.length) {
    throw new Error(`Missing env vars: ${missing.join(", ")}`);
  }
}

function makeOAuth2Client() {
  assertConfig();
  return new google.auth.OAuth2(GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, REDIRECT_URI);
}

function saveToken(clientId, token) {
  if (!clientId) {
    throw new Error("saveToken: missing clientId");
  }
  if (!token || typeof token !== "object") {
    throw new Error(`saveToken: missing token for client_id=${clientId}`);
  }  
  const p = tokenPathFor(clientId);
  fs.writeFileSync(p, JSON.stringify(token, null, 2), "utf-8");
}

function loadToken(clientId) {
  const p = tokenPathFor(clientId);
  if (!fs.existsSync(p)) return null;

  const raw = fs.readFileSync(p, "utf-8");
  return JSON.parse(raw);
}

async function getAuthorizedClient(clientId) {
  const oauth2 = makeOAuth2Client();
  const token = loadToken(clientId);
  if (!token) {
    throw new Error(`Not authorized for client_id=${clientId}. Visit /oauth/google/start?client_id=${clientId} first.`);
  }
  oauth2.setCredentials(token);

  // Ensure access token is valid / refresh if needed.
  await oauth2.getAccessToken();

  // Save updated tokens (sometimes Google returns a new access token).
  const updated = oauth2.credentials;
  if (updated && Object.keys(updated).length > 0) {
    saveToken(clientId, updated);
  }

  return oauth2;
}

function parseMaxResults(v, fallback = 5) {
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(n, 50);
}

function clampInt(v, { min, max }) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.trunc(n);
  if (i < min || i > max) return null;
  return i;
}

function cleanText(v) {
  if (typeof v !== "string") return "";
  return v.replace(/\s+/g, " ").trim();
}

function buildGmailQuery({ text, from, subject, unread_only, in_inbox, newer_than_days }) {
  const parts = [];

  // Default to inbox for voice use unless explicitly disabled
  if (in_inbox !== false) parts.push("in:inbox");
  if (unread_only === true) parts.push("is:unread");

  const fromText = cleanText(from);
  if (fromText) parts.push(`from:${fromText}`);

  const subjectText = cleanText(subject);
  if (subjectText) parts.push(`subject:(${subjectText})`);

  const nd = clampInt(newer_than_days, { min: 1, max: 365 });
  if (nd != null) parts.push(`newer_than:${nd}d`);

  const free = cleanText(text);
  if (free) parts.push(free);

  return parts.join(" ").trim();
}

function headerMap(msg) {
  const headers = msg.payload?.headers || [];
  return Object.fromEntries(headers.map((x) => [String(x.name || "").toLowerCase(), x.value || ""]));
}

function compactSnippet(s, maxLen = 180) {
  const t = String(s || "").replace(/\s+/g, " ").trim();
  if (t.length <= maxLen) return t;
  return t.slice(0, maxLen - 1) + "…";
}


//
// Exposed APIs
export function registerGmailRoutes(app) {
  // Start OAuth
  app.get("/oauth/google/start", (req, res) => {
    try {
      const oauth2 = makeOAuth2Client();

      const clientId = getClientIdFromReq(req);
      if (!clientId) {
        return res.status(400).json({ ok: false, error: "Missing or invalid client_id. Provide ?client_id=XXXX (4-80 chars: letters/digits/_/-) or header X-Client-Id." });
      }

      // prompt=consent ensures you get refresh_token (often only on first consent)
      const authUrl = oauth2.generateAuthUrl({
        access_type: "offline",
        scope: SCOPES,
        include_granted_scopes: true,
        prompt: "consent",
        state: clientId,        
      });

      console.log("REDIRECT_URI =", REDIRECT_URI);
      console.log("AUTH_URL =", authUrl);

      return res.redirect(authUrl);
    } catch (e) {
      return res.status(500).json({ ok: false, error: String(e) });
    }
  });

  // OAuth callback
  app.get("/oauth/google/callback", async (req, res) => {
    try {
      const code = req.query.code;
      if (!code || typeof code !== "string") {
        return res.status(400).json({ ok: false, error: "Missing code" });
      }

      const state = req.query.state;
      const clientId = sanitizeClientId(typeof state === "string" ? state : "");
      if (!clientId) {
        return res.status(400).json({ ok: false, error: "Missing or invalid state (client_id)." });
      }

      const oauth2 = makeOAuth2Client();
      const { tokens } = await oauth2.getToken(code);
      oauth2.setCredentials(tokens);

      // Save tokens for later Gmail calls
      saveToken(clientId, tokens);

      return res.json({ ok: true, client_id: clientId, message: "Gmail authorized. You can close this tab." });
    } catch (e) {
      return res.status(500).json({ ok: false, error: String(e) });
    }
  });

  // Search Gmail
  app.get("/gmail/search", async (req, res) => {
    try {
      const clientId = getClientIdFromReq(req);
      if (!clientId) {
        return res.status(400).json({ ok: false, error: "Missing or invalid client_id. Provide header X-Client-Id or ?client_id=..." });
      }

      const q = req.query.q;
      if (!q || typeof q !== "string") {
        return res.status(400).json({ ok: false, error: "Missing required query param: q" });
      }
      const maxResults = parseMaxResults(req.query.max_results, 5);

      const auth = await getAuthorizedClient(clientId);
      const gmail = google.gmail({ version: "v1", auth });

      const r = await gmail.users.messages.list({
        userId: "me",
        q,
        maxResults,
      });

      const msgs = r.data.messages || [];
      return res.json({ ok: true, message_ids: msgs.map((m) => m.id) });
    } catch (e) {
      return res.status(500).json({ ok: false, error: String(e) });
    }
  });

  // Search Gmail with structured parameters (voice-friendly)
  app.post("/gmail/search_structured", async (req, res) => {
    try {
      const clientId = getClientIdFromReq(req);
      if (!clientId) {
        return res.status(400).json({ ok: false, error: "Missing or invalid client_id. Provide header X-Client-Id or body.client_id." });
      }

      const body = req.body || {};

      const q = buildGmailQuery({
        text: body.text,
        from: body.from,
        subject: body.subject,
        unread_only: body.unread_only,
        in_inbox: body.in_inbox,
        newer_than_days: body.newer_than_days,
      });

      const maxResults = parseMaxResults(body.max_results, 5);

      if (!q) {
        return res.status(400).json({ ok: false, error: "Empty search. Provide at least one of: text, from, subject, unread_only, newer_than_days." });
      }

      const auth = await getAuthorizedClient(clientId);
      const gmail = google.gmail({ version: "v1", auth });

      const list = await gmail.users.messages.list({
        userId: "me",
        q,
        maxResults,
      });

      const ids = (list.data.messages || []).map((m) => m.id).filter(Boolean);
      if (ids.length === 0) {
        return res.json({ ok: true, query: q, results: [] });
      }

      const cards = await Promise.all(
        ids.map(async (id) => {
          const r = await gmail.users.messages.get({
            userId: "me",
            id,
            format: "metadata",
            metadataHeaders: ["From", "Subject", "Date"],
          });

          const msg = r.data;
          const h = headerMap(msg);

          return {
            id: msg.id,
            threadId: msg.threadId,
            subject: h["subject"] || "",
            from: h["from"] || "",
            date: h["date"] || "",
            snippet: compactSnippet(msg.snippet || ""),
          };
        })
      );

      return res.json({ ok: true, query: q, results: cards });
    } catch (e) {
      return res.status(500).json({ ok: false, error: String(e) });
    }
  });

  // Read Gmail (metadata)
  app.get("/gmail/read", async (req, res) => {
    try {
      const clientId = getClientIdFromReq(req);
      if (!clientId) {
        return res.status(400).json({ ok: false, error: "Missing or invalid client_id. Provide header X-Client-Id or ?client_id=..." });
      }

      const id = req.query.id;
      if (!id || typeof id !== "string") {
        return res.status(400).json({ ok: false, error: "Missing required query param: id" });
      }

      const auth = await getAuthorizedClient(clientId);
      const gmail = google.gmail({ version: "v1", auth });

      const r = await gmail.users.messages.get({
        userId: "me",
        id,
        format: "metadata",
      });

      const msg = r.data;
      const headers = msg.payload?.headers || [];
      const h = Object.fromEntries(headers.map((x) => [String(x.name || "").toLowerCase(), x.value || ""]));

      return res.json({
        ok: true,
        id: msg.id,
        threadId: msg.threadId,
        snippet: msg.snippet || "",
        subject: h["subject"] || "",
        from: h["from"] || "",
        date: h["date"] || "",
      });
    } catch (e) {
      return res.status(500).json({ ok: false, error: String(e) });
    }
  });



}