# Mistakes, Gotchas, and Fixes — A Running Log

Real problems we hit running local and cloud LLMs, and how we actually fixed them. Organized by component.

## llama-server / llama.cpp

### Flag syntax changed: `-fa` → `-fa on`
llama.cpp commit `b8467` (early 2026) switched bare-flag `-fa` to value-style `-fa on`. Old scripts silently broke.

### `-ctk turbo3 -ctv turbo3` requires a TurboQuant fork
Mainline llama.cpp doesn't know about turbo3. Build TheTom or Madreag for the target GPU arch. Our 5090 build command:
```bash
cmake -B build -DGGML_CUDA=ON -DGGML_NATIVE=ON -DGGML_CUDA_FA=ON \
  -DGGML_CUDA_FA_ALL_QUANTS=ON -DCMAKE_CUDA_ARCHITECTURES=120 \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

### Qwen3.6 requires `LLM_ARCH_QWEN3NEXT`
Qwen3.6's Gated DeltaNet layers use state-space model tensors (`ssm_d_conv`, `ssm_d_state`, etc.). Madreag's fork predates Qwen3NEXT arch registration — will fail to load or load incorrectly. Use TheTom's fork for Qwen3.6.

### Qwen3.5-122B infinite-thinking on bartowski Q4_K_M
Broken chat template in an older bartowski build. Model emits endless `<think>` content without ever closing the block. Fix: use the April 2026+ Unsloth UD-Q4_K_XL, which has the corrected template.

### systemd strips JSON quotes in ExecStart
```
ExecStart=.../llama-server --chat-template-kwargs '{"enable_thinking":false}'
```
systemd strips the `"` characters, llama-server sees `{enable_thinking:false}`, fails on "expected string literal". Same problem with `Environment=LLAMA_CHAT_TEMPLATE_KWARGS=...`.

**Fix**: wrap in a shell script and `ExecStart=/home/user/start-llama.sh`. Shell quoting survives systemd.

### Per-request thinking disable
Instead of disabling globally, pass `chat_template_kwargs: {"enable_thinking": false}` in the OpenAI-compatible chat body. Works for Qwen3.x and Gemma 4. Kept global thinking ON and only disabled it in the extract API.

### Qwen3.5-122B spends 3000+ tokens thinking about "hello"
Even with valid chat template, the big MoE is very verbose in reasoning mode. Adding "Think briefly then respond" to the system prompt cuts thinking from 11K chars → 400 chars. For extraction-type endpoints, always disable thinking.

## Model Tool-Calling

### Small-active-MoE can't generate tool-call JSON reliably
Qwen3.5-122B-A10B (10B active) failed to emit valid `finish_reason: "tool_calls"` under AnythingLLM's agent loop. Qwen3.5-35B-A3B (3B active) also fails. Qwen3.6-35B-A3B (3B active) is better but still unreliable for multi-step chains.

**Gemma 4 26B-A4B (4B active)** succeeds — Google specifically post-trained function calling and ships `<|tool_call>` tokenizer delimiters.

**Fix**: use Gemma 4 26B for agent tool calls, keep Qwen for chat/RAG/extraction.

### `todowrite` array-as-string quirk
Some models generate:
```json
{"todos": "[{\"content\":\"task\"}]"}   // WRONG — stringified
```
Instead of:
```json
{"todos": [{"content":"task","status":"pending","priority":"high"}]}   // RIGHT
```
Known Gemma 4 quirk. Low priority — our production code doesn't depend on `todowrite`.

### Old llama.cpp ≠ Gemma 4 tokenizer fixes
Gemma 4 tool calling needs llama.cpp built after April 3 2026 (tokenizer + chat template fixes). Also re-download GGUFs from Unsloth — they re-uploaded after the April 3 fix.

## AnythingLLM

### `host.docker.internal` needs `extra_hosts` on Linux
Docker-on-Linux doesn't resolve `host.docker.internal` automatically. Add:
```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```
to docker-compose.yml. Inside the container, host services on port N are reachable at `http://host.docker.internal:N`.

### Workspace system prompt trains refusal
A polite "You are the X Knowledge Assistant. You answer based on docs" prompt trains the model to refuse tool calls: "I'm just a knowledge assistant, I cannot browse the web." Fix: explicit "You HAVE these tools. USE them. Do not refuse."

### `@agent` prefix required for tool mode
Plain chat is RAG-only. Tools only trigger when message starts with `@agent `. Workspaces must also have `agentProvider` + `agentModel` configured (via API update).

### MCP server changes need reload
Edit `anythingllm_mcp_servers.json` → restart AnythingLLM container OR click "Reload MCP Servers" in the UI. Config is read on agent-mode invocation, not live.

## Local Desktop Automation (Windows + WSL)

### `.vbs` → PowerShell → `wsl -d kali-linux` chain: quote hell
Passing args through three layers of parsers (wscript → powershell → bash) loses escapes. Rules that actually work:
- `.vbs` file just runs `powershell.exe -NoExit -ExecutionPolicy Bypass -File "..."`
- `.ps1` file uses `wsl -d kali-linux -- bash -c "SINGLE long string"` (double quotes in PowerShell)
- Inside the bash string, use single quotes for nested strings where possible, never nest double quotes without escaping

### Shortcuts break if you move the `.vbs` files
Desktop `.lnk` shortcuts bake absolute paths to `.vbs`. After moving `testai\*.vbs` → `testai\scripts\*.vbs`, update each shortcut:
```powershell
$s = (New-Object -COM WScript.Shell).CreateShortcut($path)
$s.Arguments = '"C:\Users\...\scripts\NAME.vbs"'
$s.Save()
```

### WSL path for Windows files: `/mnt/c/...`
`C:\Users\<you>\ai\foo.gguf` → `/mnt/c/Users/<you>/ai/foo.gguf` inside WSL. Forward slashes, lowercase drive letter. Loading the model from this path is slow on first run (9p filesystem), much faster on subsequent runs (cached).

### PowerShell `Remove-Item` with bash-interpolated path = null-ref
`powershell.exe -NoProfile -Command "... Remove-Item 'path\$var'"` — bash ate `$var`. Use an actual PowerShell script file and run it with `-File`, don't inline complex logic through `-Command` from bash.

## Ollama (why we migrated away)

### Unsloth HF GGUFs don't load
Ollama 0.18.2 on Windows: "unable to load model" on any `unsloth/*-GGUF` artifact. Use llama-server instead.

### Default params are wrong for Qwen3.x coding
Ollama's Modelfile ships `temperature=1.0` and `presence_penalty=1.5` — both wrong for Qwen3.x coding. Correct: `temperature=0.6`, `presence_penalty=0.0`. The model will feel "sloppy" with Ollama defaults.

### Env vars must be system-level, not user-level
`OLLAMA_HOST`, `OLLAMA_ORIGINS`, etc. set as User env vars don't reach the Ollama tray app on Windows. Must be set as Machine (system) env vars via admin PowerShell.

## Pygame Tests (bugs we hit reviewing model output)

### Asteroids: `TypeError: Ship.__init__() missing 1 required positional argument: 'radius'`
Model generated a `@dataclass class Ship(GameObject)` where `GameObject` has `radius: float` as a required field, but `Ship.__post_init__` tried to set it after construction. Fix: pass `radius=SHIP_SIZE` in the constructor call. This kind of dataclass inheritance gotcha is a recurring failure mode in model-generated pygame code.

### Kanban: drag-and-drop broken
1. `e.preventDefault()` in `handleDragStart` cancels the drag. Remove it.
2. `loadFromStorage()` returned plain JSON objects instead of Card class instances — methods disappeared. Fix: `.map(c => new Card(c))`.

Both fixed by a follow-up prompt referencing the browser console error. Model-generated code often has this "plausible but wrong" pattern — the docs say "preventDefault on dragover to allow drop" and it over-applies the pattern.

## Context Management

### Tool-schema-tax is real
Claude Code with 50+ MCP tool schemas uses 5-10K+ tokens just for the tool list. OpenCode sends ~10 tools, much friendlier to local models. For local model work, always use OpenCode or similar lean clients.

### 131K context on 32GB 5090 is realistic for Qwen3.x MoE
Model (~21GB) + f16 KV (2.5GB) + compute (~1GB) = 24-25GB, leaving room to breathe. With TurboQuant turbo3 you can push to 262K native context with 1 slot (actually tested — 25GB VRAM at 262K).

### 131K context on Gemma 4 31B dense is cramped
KV cache for a dense 31B at 131K f16 is ~11.4GB. Model + KV = 29-30GB on a 32GB card. Works but zero headroom. Use 65K ctx if you want margin, or move to Gemma 4 26B-A4B MoE which uses far less KV.
