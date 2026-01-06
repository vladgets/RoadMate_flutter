// server/gmail.js
import fs from "fs";
import { google } from "googleapis";

const SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"];
const TOKEN_PATH = process.env.GOOGLE_TOKEN_PATH || "/tmp/google_token.json";

// REQUIRED env vars for production (don't hardcode these):
// GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, BASE_URL
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const BASE_URL = process.env.BASE_URL; // e.g. https://roadmate-flutter.onrender.com
const REDIRECT_URI = BASE_URL ? `${BASE_URL}/oauth/google/callback` : null;

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

function saveToken(token) {
  fs.writeFileSync(TOKEN_PATH, JSON.stringify(token, null, 2), "utf-8");
}

function loadToken() {
  if (!fs.existsSync(TOKEN_PATH)) return null;
  const raw = fs.readFileSync(TOKEN_PATH, "utf-8");
  return JSON.parse(raw);
}

async function getAuthorizedClient() {
  const oauth2 = makeOAuth2Client();
  const token = loadToken();
  if (!token) {
    throw new Error("Not authorized. Visit /oauth/google/start first.");
  }
  oauth2.setCredentials(token);

  // Ensure access token is valid / refresh if needed.
  // googleapis will auto-refresh on request if refresh_token exists,
  // but calling getAccessToken ensures creds are usable.
  await oauth2.getAccessToken();

  // Save updated tokens (sometimes Google returns a new access token).
  const updated = oauth2.credentials;
  if (updated) saveToken(updated);

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

      // prompt=consent ensures you get refresh_token (often only on first consent)
      const authUrl = oauth2.generateAuthUrl({
        access_type: "offline",
        scope: SCOPES,
        include_granted_scopes: true,
        prompt: "consent",
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

      const oauth2 = makeOAuth2Client();
      const { tokens } = await oauth2.getToken(code);
      oauth2.setCredentials(tokens);

      // Save tokens for later Gmail calls
      saveToken(oauth2.credentials);

      return res.json({ ok: true, message: "Gmail authorized. You can close this tab." });
    } catch (e) {
      return res.status(500).json({ ok: false, error: String(e) });
    }
  });

  // Search Gmail
  app.get("/gmail/search", async (req, res) => {
    try {
      const q = req.query.q;
      if (!q || typeof q !== "string") {
        return res.status(400).json({ ok: false, error: "Missing required query param: q" });
      }
      const maxResults = parseMaxResults(req.query.max_results, 5);

      const auth = await getAuthorizedClient();
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

      const auth = await getAuthorizedClient();
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
      const id = req.query.id;
      if (!id || typeof id !== "string") {
        return res.status(400).json({ ok: false, error: "Missing required query param: id" });
      }

      const auth = await getAuthorizedClient();
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