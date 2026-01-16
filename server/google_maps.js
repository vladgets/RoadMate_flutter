const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;

// Supported options for Google Distance Matrix `units`: "metric" or "imperial".
// Supported options for `mode` in this endpoint: "driving" or "walking".
// Note: Traffic-aware fields (duration_in_traffic) are only returned for driving requests with departure_time.
function buildTrafficSummary({ baseSeconds, liveSeconds, mode }) {
  const liveMin = Math.round(liveSeconds / 60);
  const deltaSec = liveSeconds - baseSeconds;
  const deltaMin = Math.round(deltaSec / 60);
  const ratio = baseSeconds > 0 ? liveSeconds / baseSeconds : 1.0;

  // For non-driving modes, we don't claim "traffic".
  if (mode !== "driving") {
    return {
      trafficLevel: "n/a",
      summary: `ETA is about ${liveMin} minutes.`,
    };
  }

  let trafficLevel = "light";
  if (deltaSec <= 120 || ratio < 1.1) trafficLevel = "light";
  else if (deltaSec <= 300 || ratio < 1.30) trafficLevel = "moderate";
  else if (deltaSec <= 600 || ratio < 1.50) trafficLevel = "heavy";
  else trafficLevel = "very heavy";

  if (deltaMin <= 0) {
    return {
      trafficLevel,
      summary: `ETA is about ${liveMin} minutes. Traffic is ${trafficLevel}.`,
    };
  }

  let navType = "by car";
  if (mode === "walking") navType = "on foot";

  return {
    trafficLevel,
    summary: `ETA is about ${liveMin} minutes ${navType}. Traffic is ${trafficLevel} — about ${deltaMin} minutes slower than usual.`,
  };
}

function assertNonEmptyString(value, name) {
  if (typeof value !== "string" || value.trim().length < 3) {
    throw new Error(`${name} must be a non-empty string (address or 'lat,lng').`);
  }
}

export function registerGoogleMapsRoutes(app) {
    // Traffic-aware ETA endpoint (Google Distance Matrix API)
    // POST /traffic_eta
    // body: { origin: "...", destination: "...", units?: "metric"|"imperial", mode?: "driving"|"walking" }
    app.post("/traffic_eta", async (req, res) => {
        try {
        if (!GOOGLE_MAPS_API_KEY) {
            return res.status(500).json({ ok: false, error: "Missing GOOGLE_MAPS_API_KEY env var on server" });
        }

        const {origin, destination, units = "metric", mode = "driving" } = req.body ?? {};

        assertNonEmptyString(origin, "origin");
        assertNonEmptyString(destination, "destination");

        const unitsNorm = String(units || "metric").toLowerCase();
        if (unitsNorm !== "metric" && unitsNorm !== "imperial") {
        return res.status(400).json({ ok: false, error: "Invalid units. Use 'metric' or 'imperial'." });
        }

        const modeNorm = String(mode || "driving").toLowerCase();
        if (modeNorm !== "driving" && modeNorm !== "walking") {
        return res.status(400).json({ ok: false, error: "Invalid mode. Use 'driving' or 'walking'." });
        }

        const url = new URL("https://maps.googleapis.com/maps/api/distancematrix/json");
        url.searchParams.set("origins", origin);
        url.searchParams.set("destinations", destination);
        url.searchParams.set("mode", modeNorm);
        url.searchParams.set("units", unitsNorm);

        // For driving, request traffic-aware duration.
        if (modeNorm === "driving") {
        url.searchParams.set("departure_time", "now");
        }

        // Always English (no language parameter)
        url.searchParams.set("language", "en");

        url.searchParams.set("key", GOOGLE_MAPS_API_KEY);

        const r = await fetch(url.toString(), { method: "GET" });
        const data = await r.json();

        if (!r.ok) {
        return res.status(502).json({ ok: false, error: "Google Distance Matrix request failed", details: data });
        }
        if (data?.status !== "OK") {
        return res.status(502).json({ ok: false, error: `Google status=${data?.status}`, details: data });
        }

        const element = data?.rows?.[0]?.elements?.[0];
        if (!element) {
        return res.status(502).json({ ok: false, error: "No element in response", details: data });
        }
        if (element?.status !== "OK") {
        return res.status(200).json({
            ok: false,
            elementStatus: element?.status,
            summary: "Route unavailable right now.",
        });
        }

        const distanceMeters = Number(element?.distance?.value ?? 0);
        const baseSeconds = Number(element?.duration?.value ?? 0);

        // Only present for driving + departure_time when traffic data is available.
        const liveSeconds = Number(element?.duration_in_traffic?.value ?? baseSeconds);

        const { trafficLevel, summary } = buildTrafficSummary({
        baseSeconds,
        liveSeconds,
        mode: modeNorm,
        });

        return res.status(200).json({
        ok: true,
        originAddress: data?.origin_addresses?.[0] ?? origin,
        destinationAddress: data?.destination_addresses?.[0] ?? destination,
        units: unitsNorm,
        mode: modeNorm,
        distanceMeters,
        baseSeconds,
        liveSeconds,
        trafficDeltaSeconds: Math.max(0, liveSeconds - baseSeconds),
        trafficLevel,
        summary,
        });
        } catch (e) {
            return res.status(400).json({ ok: false, error: String(e?.message ?? e) });
        }
    });
}

