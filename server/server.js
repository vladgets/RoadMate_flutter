import express from "express";

const app = express();
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
            voice: "alloy",
          },
        },
      },
    }),
  });

  const data = await r.json();
  res.json(data); // contains { value: "ek_..." }
});

app.listen(3000, () => console.log("Token server on :3000"));
