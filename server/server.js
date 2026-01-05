import express from "express";

const app = express();
app.use(express.json());
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

app.get("/token", async (req, res) => {
  const r = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      expires_after: { anchor: "created_at", seconds: 600 },
      session: {
        type: "realtime",
        model: "gpt-realtime-mini-2025-12-15",
        output_modalities: ["audio"],
        audio: {
          input: {
            turn_detection: { type: "server_vad" },
          },
          output: {
            voice: "marin",
          },
        },
      },
    }),
  });

  const data = await r.json();
  res.json(data); // contains { value: "ek_..." }
});

// web search endpoint (using OpenAI Responses API with web search tool)
app.post("/websearch", async (req, res) => {
  try {
    const { query, model } = req.body ?? {};
    if (!query || typeof query !== "string") {
      return res.status(400).json({ ok: false, error: "Missing required field: query" });
    }

    const r = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: model || "gpt-4.1-mini",
        input:
          "Search the web for accurate, up-to-date information for the query. " +
          "Return 3-5 results as short snippets (1-2 sentences each) suitable for voice. " +
          "Prefer authoritative sources. Query: " +
          query,
        tools: [{ type: "web_search" }],
      }),
    });

    const data = await r.json();

    // Best-effort extraction of search results from the Responses output.
    // The exact structure can evolve, so we keep it defensive.
    const results = [];
    const output = Array.isArray(data?.output) ? data.output : [];

    for (const item of output) {
      // Some responses include a tool call item with a `results` array.
      const maybeResults = item?.results;
      if (Array.isArray(maybeResults)) {
        for (const rr of maybeResults) {
          const title = rr?.title ?? rr?.name ?? "";
          const url = rr?.url ?? rr?.link ?? "";
          const snippet = rr?.snippet ?? rr?.content ?? rr?.text ?? "";
          if (title || url || snippet) {
            results.push({ title, url, snippet });
          }
        }
      }
    }

    // Fallback: if we couldn't parse structured results, return the raw payload.
    if (results.length === 0) {
      return res.status(200).json({ ok: true, query, results: [], raw: data });
    }

    res.status(200).json({ ok: true, query, results });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e) });
  }
});


app.listen(3000, () => console.log("Token server on :3000"));
