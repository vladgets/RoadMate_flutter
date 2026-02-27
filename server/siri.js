/**
 * Siri/Shortcuts Integration Endpoint
 *
 * Handles voice requests from Apple Shortcuts and Android quick actions.
 * Processes text input, calls OpenAI with RoadMate tools, returns text response.
 */

import OpenAI from "openai";

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

const openai = new OpenAI({ apiKey: OPENAI_API_KEY });

// System prompt for quick voice interactions
const SYSTEM_PROMPT = `You are RoadMate, a helpful voice assistant for drivers.

Keep responses SHORT (1-3 sentences) since they will be spoken aloud.
Be friendly, helpful, and concise.

You can help with:
- Answering questions
- Web searches for current information
- General assistance

If the user asks about location, calendar, reminders, or navigation, tell them to open the RoadMate app for full functionality.`;

// Tools available for Siri/Shortcut requests
const TOOLS = [
  {
    type: "function",
    function: {
      name: "web_search",
      description: "Search the web for current information",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "The search query",
          },
        },
        required: ["query"],
      },
    },
  },
];

// Simple in-memory chat history (per client_id)
const chatHistory = new Map();
const MAX_HISTORY = 10;

function getHistory(clientId) {
  if (!chatHistory.has(clientId)) {
    chatHistory.set(clientId, []);
  }
  return chatHistory.get(clientId);
}

function addToHistory(clientId, role, content) {
  const history = getHistory(clientId);
  history.push({ role, content });
  // Keep only last N messages
  while (history.length > MAX_HISTORY) {
    history.shift();
  }
}

function clearHistory(clientId) {
  chatHistory.delete(clientId);
}

// Web search implementation (reuses existing endpoint logic)
async function performWebSearch(query) {
  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        input:
          "Search the web and provide a brief, voice-friendly answer (1-2 sentences). Query: " +
          query,
        tools: [{ type: "web_search" }],
      }),
    });

    const data = await response.json();

    // Extract answer from response
    const output = Array.isArray(data?.output) ? data.output : [];
    let answer = "";

    for (const item of output) {
      if (item?.type !== "message") continue;
      const content = Array.isArray(item?.content) ? item.content : [];
      for (const c of content) {
        if (c?.type === "output_text" && typeof c?.text === "string") {
          answer += c.text;
        }
      }
    }

    // Clean URLs from answer
    answer = answer
      .replace(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g, "$1")
      .replace(/https?:\/\/\S+/g, "")
      .replace(/\s{2,}/g, " ")
      .trim();

    return answer || "I couldn't find information about that.";
  } catch (e) {
    console.error("[Siri] Web search error:", e);
    return "Sorry, I couldn't search for that right now.";
  }
}

// Main handler for Siri/Shortcut requests
async function handleSiriRequest(input, clientId = "default") {
  const trimmedInput = (input || "").trim();

  if (!trimmedInput) {
    return "I didn't catch that. What would you like help with?";
  }

  // Check for clear/reset commands
  if (/^(clear|reset|new chat|start over)$/i.test(trimmedInput)) {
    clearHistory(clientId);
    return "Chat cleared. How can I help you?";
  }

  try {
    // Add user message to history
    addToHistory(clientId, "user", trimmedInput);

    // Build messages array
    const messages = [
      { role: "system", content: SYSTEM_PROMPT },
      ...getHistory(clientId),
    ];

    // Call OpenAI
    const response = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages,
      tools: TOOLS,
      tool_choice: "auto",
      temperature: 0.7,
      max_tokens: 300,
    });

    const choice = response.choices[0];
    const message = choice.message;

    // Handle tool calls
    if (message.tool_calls && message.tool_calls.length > 0) {
      const toolCall = message.tool_calls[0];

      if (toolCall.function.name === "web_search") {
        const args = JSON.parse(toolCall.function.arguments);
        const searchResult = await performWebSearch(args.query);

        // Add tool result to conversation and get final response
        const followUp = await openai.chat.completions.create({
          model: "gpt-4o-mini",
          messages: [
            ...messages,
            message,
            {
              role: "tool",
              tool_call_id: toolCall.id,
              content: searchResult,
            },
          ],
          temperature: 0.7,
          max_tokens: 300,
        });

        const finalResponse = followUp.choices[0].message.content || searchResult;
        addToHistory(clientId, "assistant", finalResponse);
        return finalResponse;
      }
    }

    // Regular response
    const assistantResponse = message.content || "I'm not sure how to help with that.";
    addToHistory(clientId, "assistant", assistantResponse);
    return assistantResponse;

  } catch (e) {
    console.error("[Siri] Error:", e);
    return "Sorry, I encountered an error. Please try again.";
  }
}

// Register routes
export function registerSiriRoutes(app) {
  // Main Siri/Shortcut endpoint
  app.post("/siri", async (req, res) => {
    try {
      const { input, text, query, client_id } = req.body || {};
      const userInput = input || text || query || "";
      const clientId = client_id || req.headers["x-client-id"] || "default";

      const response = await handleSiriRequest(userInput, clientId);

      res.json({
        ok: true,
        response,
        // Include speech-friendly version (same for now)
        speech: response,
      });
    } catch (e) {
      console.error("[Siri] Endpoint error:", e);
      res.status(500).json({
        ok: false,
        error: "Something went wrong",
        response: "Sorry, I couldn't process that request.",
      });
    }
  });

  // Health check for Shortcuts
  app.get("/siri/health", (req, res) => {
    res.json({ ok: true, service: "RoadMate Siri Integration" });
  });

  // Clear chat history
  app.post("/siri/clear", (req, res) => {
    const clientId = req.body?.client_id || req.headers["x-client-id"] || "default";
    clearHistory(clientId);
    res.json({ ok: true, message: "Chat history cleared" });
  });
}
