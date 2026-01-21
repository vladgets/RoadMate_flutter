import admin from "firebase-admin";

// In-memory stores for MVP/demo. In production replace with DB/Redis.
const userToFcmToken = new Map(); // user_id -> fcm_token

// request_id -> { from_user_id, to_user_id, resolve, timer }
const inflight = new Map();

function randomId() {
  return Math.random().toString(16).slice(2) + Date.now().toString(16);
}

export function registerUserLocationRoutes(app) {

  app.post("/device/register_token", (req, res) => {
    const { user_id, fcm_token } = req.body || {};
    if (!user_id || !fcm_token) return res.status(400).json({ error: "missing user_id or fcm_token" });
    userToFcmToken.set(user_id, fcm_token);
    res.json({ ok: true });
  });

  // 1) Parent-side: one-call API used by your realtime tool
  app.post("/family/location_query", async (req, res) => {
    const { from_user_id, to_user_id, timeout_ms } = req.body || {};
    if (!from_user_id || !to_user_id) return res.status(400).json({ error: "missing from_user_id or to_user_id" });

    const token = userToFcmToken.get(to_user_id);
    if (!token) return res.status(404).json({ error: "target user has no registered token" });

    const request_id = randomId();
    const waitMs = Math.max(1000, Math.min(timeout_ms ?? 6000, 15000)); // clamp 1s..15s
    // console.log("request_id", request_id);

    // Create a promise that completes when daughter responds (or timeout)
    const resultPromise = new Promise((resolve) => {
      const timer = setTimeout(() => {
        inflight.delete(request_id);
        resolve({ status: "timeout" });
      }, waitMs);

      inflight.set(request_id, { from_user_id, to_user_id, resolve, timer });
    });

    // Send silent/data push to daughter
    const message = {
      token,
      android: { priority: "high" },
      apns: {
        headers: {
          "apns-push-type": "background",
          "apns-priority": "10",
        },
        payload: { aps: { "content-available": 1 } },
      },
      data: {
        type: "family_location_ping",
        request_id,
        from_user_id,
        to_user_id,
      },
    };

    try {
      await admin.messaging().send(message);
    } catch (e) {
      // If we failed to send, stop waiting immediately
      const entry = inflight.get(request_id);
      if (entry) {
        clearTimeout(entry.timer);
        inflight.delete(request_id);
      }
      return res.status(500).json({ status: "send_failed", error: String(e) });
    }

    // Wait for daughter's reply or timeout
    const result = await resultPromise;
    res.json({ request_id, ...result });
  });

  // 2) Daughter-side: replies here (hardcoded now, real GPS later)
  app.post("/family/location_response", (req, res) => {
    const { request_id, to_user_id, location, source } = req.body || {};
    if (!request_id || !to_user_id || !location) return res.status(400).json({ error: "missing request_id/to_user_id/location" });

    const entry = inflight.get(request_id);
    if (!entry) {
      // Either timed out already or unknown request
      return res.json({ ok: true, ignored: true });
    }
    if (entry.to_user_id !== to_user_id) return res.status(403).json({ error: "to_user_id mismatch" });

    clearTimeout(entry.timer);
    inflight.delete(request_id);

    entry.resolve({
      status: "ok",
      location,
      source: source ?? "unknown",
      received_at: new Date().toISOString(),
    });

    res.json({ ok: true });
  });
}
