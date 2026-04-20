# Cloud Server Findings — RTX PRO 6000 96GB (Blackwell, SM120)

A chronological account of what was tried on a cloud GPU server, what broke, and what finally worked. Same llama.cpp toolchain as the local 5090, but larger models and a Docker-based RAG stack (AnythingLLM) on top.

## Machine
- NVIDIA RTX PRO 6000 Blackwell Server Edition, 96 GB VRAM, SM120
- Ubuntu 24.04, CUDA 13.0 (with 12.8 compat libs installed)
- 464 GB disk
- Cloudflare Tunnel routes subdomains for `llm.`, `knowledge.`, `extract.`

## Model Evolution (chronological)

### Round 1 — Gemma 4 31B Q8_0 (starting point)
- 32.6 GB Q8_0 load, 131K ctx, 2 slots
- Great chat quality, worked as the initial "cloud answer" LLM
- Problem: thinking mode on Gemma 4 emits `<think>` blocks that mix into JSON extraction output
- Fix attempted: `chat_template_kwargs: {"enable_thinking": false}` per-request for the extract API only
- User rejected "disable globally" → reverted to per-request only

### Round 2 — Qwen3.5-122B-A10B (tried for reasoning+tools)
- **bartowski Q4_K_M (75 GB)**: infinite thinking loop on even `"hello"` prompts. Spent 3000+ tokens of reasoning, never emitted the response. Broken chat template in that specific GGUF build.
- **Unsloth UD-Q4_K_XL (72 GB)**: fixed chat template (March 2026 update), worked. But 10B active MoE could not reliably generate tool-call JSON for AnythingLLM's agent loop — kept looping, writing same file, refusing to stop. AnythingLLM's own docs warn about quantized models and JSON generation; the 10B active size isn't enough for their agent schema demands.
- Secured the endpoint with `--api-key` to the same Bearer token as the extract API. Without it, `https://llm.example.com/v1/chat/completions` was open to the world.
- TurboQuant build (Madreag fork) loaded Unsloth UD tensors cleanly — no compatibility issues despite the "UD" custom tensor concern.

### Round 3 — Gemma 4 26B-A4B (current winner for agent tools)
- 26.9 GB Q8_0, 30.5 GB loaded with 262K native context and 4 parallel slots
- Only 4B active params per token (MoE, 128 total experts, 8 active + 1 shared, 1 vision tower)
- Native function calling trained in — AnythingLLM's `@agent` mode actually emits valid tool_calls JSON and sets `finish_reason: "tool_calls"`
- First-try tool call test: "Search the web for latest Qwen news" → clean `{"name":"web_search","arguments":"{\"query\":\"latest Qwen news\"}"}` with 162 t/s generation
- llama.cpp rebuilt from master (post-April-3) for Gemma 4 tokenizer fixes

## Services Inventory (current)

| Service | Port | Auth | Purpose |
|---|---|---|---|
| llama-server (systemd) | 8000 | Bearer token via `--api-key` | Gemma 4 26B-A4B Q8_0, 4 slots, 262K |
| AnythingLLM (Docker) | 3001 | Workspace login | RAG workspace + `@agent` mode for tool use |
| extract-api.py (systemd) | 8001 | Bearer token | `/extract` (text→JSON) + `/extract-pdf` (PDF→OCR→JSON) |
| mistral-ocr-mcp.py (systemd) | 8002 | None (internal) | FastMCP SSE server wrapping Mistral OCR API |
| Cloudflare tunnel (systemd) | — | per-route | Routes `llm.`, `knowledge.`, `extract.` subdomains |

All five systemd services are `enabled` and survive reboot. Docker container is `restart: unless-stopped`.

## Key Gotchas That Cost Hours

### systemd + JSON args don't mix
`--chat-template-kwargs '{"enable_thinking":false}'` in `ExecStart=` has its double quotes stripped by systemd's unit parser before reaching llama-server, which then errors on "invalid JSON". Same story for `Environment=LLAMA_CHAT_TEMPLATE_KWARGS=...`.

**Fix**: wrap in a shell script (`start-llama.sh`) and `ExecStart=/path/to/start-llama.sh`. Shell quoting preserves everything correctly.

### Qwen3.5-122B thinking can run away
Without an explicit `enable_thinking: false` per request, the 122B would use 3k+ tokens just thinking about a 3-word prompt. Workarounds tried:
- `--chat-template-kwargs` at server level (broken, see above)
- `chat_template_kwargs: {"enable_thinking": false}` per request via API → works
- "/no_think" at start of user message → unreliable on Qwen3.5-122B

This is the motivation for keeping the default thinking ON and disabling per-request only for pure extraction. Users who chat still get reasoning; extractor doesn't waste tokens.

### bartowski ≠ Unsloth ≠ all the same GGUF
We had assumed any Q4_K_M quant was interchangeable. Not true. The bartowski Qwen3.5-122B-A10B-Q4_K_M was built before the chat template fix and Unsloth's post-fix UD-Q4_K_XL behaves completely differently. Always check the "updated" date on the HF page and read the discussion tab.

### AnythingLLM MCP + Docker networking
MCP servers live outside the container. Inside the container, `localhost` is just the container. Must use `host.docker.internal` — and on Linux that needs `extra_hosts: - "host.docker.internal:host-gateway"` in docker-compose.

### Workspace system prompt is a real thing
A helpful-sounding "You are the [X] AI Knowledge Assistant" prompt was training the model to REFUSE tool calls ("I'm just a knowledge assistant, I can't browse"). Had to explicitly say: "You have the following tools: ... Use them. Do not refuse based on your description above."

## Build: TurboQuant on Cloud Server

Same as local, but with the cloud model targets:

```bash
# Madreag fork (works for Qwen3.5-122B, not Qwen3.6 Gated DeltaNet)
git clone --depth 1 https://github.com/Madreag/turbo3-cuda.git ~/llama-cpp-turboquant
cd ~/llama-cpp-turboquant
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120 \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

For Qwen3.6 support, switch to TheTom's fork (same cmake invocation).

## Mistral OCR MCP Pattern

See `configs/mistral-ocr-mcp.py` for the full template. Key points:
- FastMCP's `mcp.run(transport="sse")` binds an uvicorn server automatically
- Two tools exposed: `ocr_pdf_base64` and `ocr_pdf_url`
- Uses Mistral's two-step upload → signed-URL flow (the direct base64 path is less reliable)
- API key comes from `$MISTRAL_API_KEY` env, never hardcoded
- Runs as a systemd unit on port 8002, registered in AnythingLLM's `anythingllm_mcp_servers.json`

## Extract API Pattern

See `configs/extract-api.py` for the full template. Key points:
- Single `/extract` endpoint for text input, `/extract-pdf` for PDF (routes through Mistral OCR)
- Bearer token auth against the same token used by llama-server
- Sends `chat_template_kwargs: {"enable_thinking": false}` so extraction is fast and deterministic
- Strips any stray `<think>` blocks and markdown fences from the LLM output before JSON parsing
- Returns the parsed JSON directly, 500 on LLM failure

## Lessons Applied to the Local Setup
- The TheTom vs Madreag fork choice (Qwen3.6 needs Gated DeltaNet arch) applies equally to 5090 local
- systemd wrapper-script pattern is used for the local desktop shortcut launchers too (via `.vbs` → PowerShell → `wsl -d kali-linux` chain — the same escape-hell problem shows up in PowerShell + bash)
- Don't trust any model to generate complex nested JSON under `todowrite`-style tools if it's below ~10B active params
