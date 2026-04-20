# AnythingLLM Integration — Setup, MCP, Agent Mode

How to connect [AnythingLLM](https://anythingllm.com) to a local or cloud llama-server, wire up a custom MCP server, and get `@agent` tool calls working. All notes come from running the stack behind a Cloudflare Tunnel on an RTX PRO 6000 96GB server.

## Stack Overview

```
Browser (user)
   │
   ▼
knowledge.example.com (Cloudflare Tunnel — or any reverse proxy)
   │
   ▼
AnythingLLM (Docker, port 3001)
   │  chat LLM ──────► http://host.docker.internal:8000/v1  (llama-server, Bearer auth)
   │  agent LLM ─────► (same endpoint, can be different model)
   │  MCP tools ─────► http://host.docker.internal:8002/sse  (mistral-ocr)
   │
   └─► LanceDB (embedded, under /app/server/storage/vector-db)
```

## Docker Compose

```yaml
services:
  anythingllm:
    image: mintplexlabs/anythingllm
    ports:
      - "3001:3001"
    volumes:
      - anythingllm-storage:/app/server/storage
      - ./knowledge-base:/app/knowledge-base:ro
    environment:
      - STORAGE_DIR=/app/server/storage
      - LLM_PROVIDER=generic-openai
      - GENERIC_OPEN_AI_BASE_PATH=http://host.docker.internal:8000/v1
      - GENERIC_OPEN_AI_MODEL_PREF=gemma-4-26B-A4B-it-Q8_0
      - GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=262144
      - GENERIC_OPEN_AI_API_KEY=${API_TOKEN}
      - EMBEDDING_ENGINE=native
      - EMBEDDING_MODEL_PREF=nomic-embed-text-v1.5
      - VECTOR_DB=lancedb
      - AUTH_TOKEN=${ANYTHINGLLM_AUTH_TOKEN}
      - JWT_SECRET=${JWT_SECRET}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
```

**Critical**: `extra_hosts` is required on Linux to make `host.docker.internal` resolve. On Windows/Mac Docker it's automatic.

## MCP Servers Configuration

File (inside the container): `/app/server/storage/plugins/anythingllm_mcp_servers.json`

```json
{
  "mcpServers": {
    "mistral-ocr": {
      "type": "sse",
      "url": "http://host.docker.internal:8002/sse"
    }
  }
}
```

Our Mistral OCR MCP server runs as a separate systemd unit on the host (see `configs/mistral-ocr-mcp.py`). AnythingLLM auto-detects the config and connects on boot; you can restart/reload from the UI → Tools page.

### MCP Transport Types
- **stdio**: command-based, AnythingLLM spawns the process. Doesn't work well across the Docker/host boundary — host commands aren't visible inside the container.
- **sse** / **streamable**: HTTP-based. What we use for cross-container MCP servers. The URL must be reachable from inside the container (`host.docker.internal:PORT`).

## Workspace System Prompt (what works)

The default "You are the X Knowledge Assistant" framing trained the model to refuse tool use. We replaced it with this:

```
You are the [Project] AI Knowledge Assistant with access to tools and skills.
You can and should use your available tools when asked.

Capabilities you HAVE and MUST USE when relevant:
- Web search (use it when asked about current events, news, or external information)
- PDF generation / file creation (use when asked to create documents)
- MCP tools including [Mistral OCR] (use for PDF text extraction)
- RAG over [N] internal documents

When a user asks you to do something that requires a tool, USE THE TOOL.
Do not say you cannot do it. You are an agent with real tool access.

For knowledge questions: cite which document your answer comes from. If the
knowledge base does not contain the answer, say so clearly. Use structured formatting.

For tool requests: call the appropriate tool immediately without explaining why you cannot.
```

Set via the API:
```bash
curl -X POST http://localhost:3001/api/v1/workspace/$SLUG/update \
  -H "Authorization: Bearer $ANYTHINGLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"openAiPrompt": "... prompt above ...", "agentProvider": "generic-openai", "agentModel": "gemma-4-26B-A4B-it-Q8_0"}'
```

## Using @agent Mode

Plain chat: just type normally. RAG retrieves top-N chunks from the workspace's embedded docs and the model answers.

Tool mode: prefix with `@agent`:
```
@agent search the web for today's news and summarize top 3 headlines
@agent use ocr_pdf_url to extract text from https://example.com/document.pdf
@agent create a markdown file titled "summary.md" with today's findings
```

Without `@agent` prefix, the model will NEVER call tools — it's purely RAG chat.

## Tool-Call Reliability by Model

| Model | Runs on | Result |
|---|---|---|
| Qwen3.5-122B-A10B (10B active MoE) | Cloud | Loops infinitely, writes same file 4× times, can't stop |
| Qwen3.5-35B-A3B (3B active MoE) | Local | Similar looping, refuses simple tool calls |
| Qwen3.6-35B-A3B (3B active MoE) | Local | Better — sometimes works, sometimes loops on complex chains |
| **Gemma 4 26B-A4B** (4B active MoE) | **Cloud** | **Clean** — single `tool_calls` response, correct args, stops after result |

Why Gemma 4 26B works where Qwen MoE doesn't (both are similar active-param sizes): Google specifically post-trained native function calling into Gemma 4. The tokenizer has `<|tool_call>` delimiters. Unsloth updated GGUFs on 2026-04-03 to fix these delimiters in older conversions. **Always re-download Unsloth Gemma 4 GGUFs if you got them before April 2026.**

## When Tool Use Fails

AnythingLLM's own docs ([Agent Not Using Tools](https://docs.anythingllm.com/agent-not-using-tools)) cover the common failure modes:

1. **Hallucinated tool call** — Model pretends it called a tool but no "thought" chain appears in the UI. Fix: larger quant, less restrictive system prompt, or switch agent model to cloud API.
2. **"I cannot do X" refusal** — Alignment overfitting. Fix: explicit "you HAVE these tools" system prompt (see above).
3. **Infinite loop / no response** — Model emits invalid JSON that AnythingLLM can't parse. Fix: larger/unquantized model, or swap to a different agent model.
4. **`todowrite` array-as-string** — Known Gemma 4 quirk where it stringifies nested JSON arrays. Our current fix: accept it for the `tests/` folder experiments, don't rely on `todowrite` in production agent workflows.

## Recommended Setup

- **Chat LLM**: Qwen3.6-35B-A3B OR Gemma 4 26B-A4B — both work great for RAG chat
- **Agent LLM**: Gemma 4 26B-A4B (local/cloud) or Claude/GPT (cloud API) — avoid Qwen for agent mode
- **Embedding**: `nomic-embed-text-v1.5` (native, bundled)
- **Vector DB**: LanceDB (native, bundled)
- **MCP**: Your own SSE servers on the host, reference via `host.docker.internal:PORT/sse`
- **System prompt**: Explicit about tools + no refusal training

## Debugging Commands

```bash
# Check MCP servers connected
docker exec ANYTHINGLLM_CONTAINER cat /app/server/storage/plugins/anythingllm_mcp_servers.json

# Check workspace config
curl -s http://localhost:3001/api/v1/workspace/$SLUG \
  -H "Authorization: Bearer $API_KEY" | python3 -m json.tool

# Test MCP SSE reachability from inside container
docker exec ANYTHINGLLM_CONTAINER curl -s --max-time 3 http://host.docker.internal:8002/sse | head

# Watch tool-call events (user must click "agent" toggle in UI to see thoughts)
```
