# Tool Ecosystem Comparison for Local AI Coding

## Overview

We tested 5 different tools connected to local (Qwen3.5/3.6, Gemma 4) and cloud (Qwen3.5-122B, Gemma 4 26B-A4B) models running via llama-server. Here's what works and what doesn't.

## Tool Comparison

| Feature | OpenCode | Claude Code | OpenClaw | Open WebUI | AnythingLLM |
|---|---|---|---|---|---|
| **Best for** | Agentic coding | Cloud API coding | Chat via messaging | Browser chat | RAG + workspace docs |
| **Local model support** | Excellent | Limited | Good | Excellent | Good (chat/RAG), poor (agent) |
| **Tool count** | ~10 (lean) | 50+ (bloated) | Configurable | N/A | Built-in skills + MCP |
| **MCP support** | Yes | Yes | Yes | No | Yes (SSE + stdio) |
| **File editing** | Yes | Yes | Via workspace | No | Agent skill only |
| **Terminal access** | Yes | Yes | Yes | No | No |
| **Browser verification** | Chrome DevTools MCP | Chrome DevTools MCP | No | No | No |
| **Docs lookup** | Context7 MCP | Context7 MCP | No | Web search | RAG workspace |
| **Connection** | OpenAI-compatible API | Anthropic API | Ollama/OpenAI API | OpenAI-compatible | OpenAI-compatible |
| **Why it works/fails** | Lean tools = fast | Too many MCP tools tax context | Native Ollama API for tools | Simple chat, no tools | Chat/RAG fine. Agent loop requires strict tool-call JSON — smaller models hallucinate or loop. |

## Model Selection per Tool

Both Qwen3.5 and Gemma 4 work with all tools, but the sweet spots differ:

| Tool | Best Model | Why |
|---|---|---|
| OpenCode (agentic) | Qwen3.5 | 3x faster, many tool calls benefit from speed |
| OpenCode (quality tasks) | Gemma 4 | Switch model ID in config for quality-critical work |
| Claude Code | Cloud API | Local models struggle with 50+ tool schemas regardless |
| OpenClaw | Either | Chat-only, no tools — quality matters more than speed |
| Open WebUI | Either | Simple chat interface, user preference |

To switch models in OpenCode, change the `"model"` field in `opencode.json`:
- `"llama.cpp/qwen3.5-coding"` for speed
- `"llama.cpp/gemma-4-31B"` for quality

Both model entries are pre-configured in the template config.

## OpenCode (Recommended for Local Models)

**Repository**: [opencode.ai](https://opencode.ai) | [GitHub](https://github.com/opencode-ai/opencode)

### Why it's best for local models:
- Lean tool set: read, write, edit, bash, grep, glob, list, webfetch, websearch
- Each tool has a small schema footprint (~100 tokens vs 500+ for complex MCP tools)
- MCP servers add tools on demand (Context7, Chrome DevTools)
- Permission system: `"*": "allow"` for full autonomy

### MCP Servers Tested:

**Context7** ([context7.com](https://context7.com))
- Documentation search via MCP
- Works well with local models — add `use context7` to prompts
- Free tier available, API key for higher limits
- Config: `"type": "remote", "url": "https://mcp.context7.com/mcp"`

**Chrome DevTools MCP** ([GitHub](https://github.com/anthropics/anthropic-cookbook))
- Browser automation: navigate, screenshot, run JS, check console
- Auto-launches Chromium with `--executablePath`
- Key flags: `--executablePath /usr/bin/chromium --chromeArg --no-sandbox`
- NOT `--cdp-url` or `--browserUrl` for auto-launch mode

### Agent Capabilities Tested:

#### With Qwen3.5-35B-A3B:
1. **Asteroids game** (519 lines) — Single prompt, zero-shot. Worked with minor fixes needed.
2. **Crypto dashboard** (629 lines) — Used Context7 for CoinGecko API docs. Chrome DevTools failed to connect (wrong MCP flag).
3. **Kanban board** (1,717 lines) — Used Context7 for Drag & Drop API. Found 2 bugs: `preventDefault` on dragstart, localStorage deserialization. Fixed with follow-up prompt.
4. **JWT Auth Next.js app** — Full stack: SQLite + bcrypt + jose + middleware. Built and ran successfully.

#### With Gemma 4 31B:
1. **Asteroids game** — **Worked perfectly on first try**, zero bugs. Higher first-shot quality than Qwen3.5.
2. Slower iteration cycle (61 t/s vs 188 t/s), but fewer iterations needed due to better output quality.

## Claude Code with Local Models

**Repository**: [claude.ai/code](https://claude.ai/code) | [GitHub](https://github.com/anthropics/claude-code)

### The Problem:
Claude Code sends ALL connected MCP tool schemas to the model with every request. If you have Notion, Slack, Atlassian, Gmail, Figma, Excalidraw connected, that's 50+ tool schemas consuming thousands of tokens of context.

### GBNF Grammar Overhead:
llama-server builds constrained grammars for each tool. With 50+ tools, the grammar compilation alone takes seconds and the schemas consume 5-10K+ tokens of the model's context window.

### When it works:
- With Anthropic's cloud API (designed for large context + many tools)
- With local models IF you disconnect all MCP servers except essentials
- Via `claude-qwen` bash function for quick tasks

### Tool Support Requirement:
Local models need proper chat template support for tool calling. In Ollama, this requires `RENDERER qwen3.5` and `PARSER qwen3.5`. llama-server handles this automatically via the embedded chat template.

## OpenClaw (Telegram Bot)

**Documentation**: [docs.ollama.com](https://docs.ollama.com)

### Setup Notes:
- Use `api: "openai-completions"` with llama-server (NOT native Ollama API)
- Native Ollama API (`/api/chat`) requires actual Ollama running
- `dmPolicy: "open"` for easy access, or `"pairing"` for security
- Gateway requires systemd in WSL (`/etc/wsl.conf` -> `systemd=true`)
- WSL systemd user sessions are fragile — `wsl -d` commands can crash them

### Limitations with Local Models:
- Tool calling reliability depends on model's training for tool use
- Both Qwen3.5 and Gemma 4 handle tools well with proper chat templates
- Keep tool count low (same principle as OpenCode)

## AnythingLLM (Enterprise RAG + Agent Platform)

**Repository**: [anythingllm.com](https://anythingllm.com) | [GitHub](https://github.com/Mintplex-Labs/anything-llm)

### What It Is
Docker-deployed platform with workspaces, RAG over a document collection (LanceDB), agent mode with MCP tools, and role-based access control. Tested behind a reverse proxy on a cloud RTX PRO 6000 server with a custom markdown document collection.

### Setup Gotchas Discovered
- Connect to llama-server via `host.docker.internal:PORT` — requires `extra_hosts: - "host.docker.internal:host-gateway"` in docker-compose.yml on Linux.
- MCP servers are configured via `/app/server/storage/plugins/anythingllm_mcp_servers.json` inside the container. SSE servers on the host reachable at `http://host.docker.internal:PORT/sse`.
- Workspace system prompt is stored in `openAiPrompt` field (`POST /api/v1/workspace/:slug/update`). A restrictive "you are a knowledge assistant" prompt will make the model refuse tool calls — add explicit "you have tools, use them" framing.
- Agent model can be set separately from chat model via `agentProvider` + `agentModel` fields.
- Users must prefix messages with `@agent` to trigger agent/tool mode; plain chat never calls tools.

### Tool Calling Reliability (by model)
Agent mode generates function-call JSON and expects the model to emit valid schema-matching JSON with `finish_reason: "tool_calls"`. Our findings:

| Model | Agent tools | Reason |
|---|---|---|
| **Qwen3.5-122B-A10B** (MoE, 10B active) | ❌ Loops or refuses | Even thinking disabled, MoE's effective 10B capacity isn't enough for reliable tool-call JSON under AnythingLLM's full schema injection. `todowrite` double-encodes arrays as strings. |
| **Qwen3.5-35B-A3B** | ❌ Similar loops | 3B active is too small for complex tool schemas |
| **Qwen3.6-35B-A3B** | Partial | Better than 3.5 with updated chat template, still unreliable for multi-step agent loops |
| **Gemma 4 26B-A4B** (MoE, 4B active) | ✅ Works | Google trained native function calling into the post-training. `finish_reason: "tool_calls"` emits cleanly with correct JSON. |
| **Gemma 4 31B** (dense) | Not tested | Dense model, likely similar to Qwen in tool JSON weakness |
| Cloud API (Claude, GPT) | ✅ Works | Recommended by AnythingLLM docs for agent calls |

### Recommended Config
- **Chat model**: Qwen3.6-35B-A3B (fast, good RAG)
- **Agent model**: Gemma 4 26B-A4B OR cloud API (for reliable tool calls)
- **MCP**: Custom SSE servers on host (e.g., Mistral OCR), auth via shared Bearer token
- **System prompt**: Explicit about available tools + how to use them

See `research/anythingllm-integration.md` for the full setup walkthrough.

## Open WebUI (Chat Interface)

**Repository**: [github.com/open-webui/open-webui](https://github.com/open-webui/open-webui)

### Setup:
- Docker container, connects via `host.docker.internal:10500` (WSL/Windows) or `172.17.0.1:10500` (native Linux)
- Simple chat interface, no agentic capabilities
- Good for casual conversations and testing model quality
- Supports multiple models if you have them loaded
- See `configs/open-webui-docker.sh` for networking details
