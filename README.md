# Local AI Coding Pipeline — RTX 5090 + Cloud GPU + Qwen3.6 + TurboQuant

A complete guide to building a fully local AI-powered coding environment that runs on your hardware — plus an optional cloud GPU server for heavier models and enterprise RAG.

## What This Is

A production-ready AI coding setup spanning two machines:

### Local (RTX 5090, 32GB) — **Updated April 2026**
- **Qwen3.6-35B-A3B** (primary) — MoE (3B active, 8 routed + 1 shared experts, 256 total). Hybrid **Gated DeltaNet + Gated Attention** architecture (30 linear + 10 full attention layers). Native 262K context, extensible to 1M. **~177 t/s** generation with TurboQuant turbo3. Native tool calling + developer role support (Codex/OpenCode).
- **Qwen3.5-35B-A3B** (legacy) — MoE (3B active), 188 t/s generation.
- **Gemma 4 31B** — Dense (31B active), 61 t/s generation. Best quality/reasoning for single-shot tasks.

### Cloud (RTX PRO 6000, 96GB)
- **Qwen3.5-122B-A10B** — MoE (10B active), Unsloth UD-Q4_K_XL (72GB) + **TurboQuant turbo3** KV compression. Better benchmarks, tool use, and reasoning than the 35B variant. Unsloth's latest GGUFs include fixed chat templates for tool-calling/coding.
- **AnythingLLM** — RAG knowledge base with workspaces, RBAC, and agent skills
- **Mistral OCR MCP** — PDF text extraction via Mistral API as an MCP tool for AnythingLLM agents
- **Extract API** — PDF → OCR → LLM extraction → clean structured-JSON pipeline

Both powered by **llama-server** with Google's **TurboQuant** KV cache compression. The local RTX 5090 uses **[TheTom's fork](https://github.com/TheTom/llama-cpp-turboquant)** (has `LLM_ARCH_QWEN3NEXT` for Gated DeltaNet support — required for Qwen3.6); the cloud server uses **[Madreag's fork](https://github.com/Madreag/turbo3-cuda)** (+13-69% faster decode at 32K on SM120 for non-hybrid models).

**Tools:**
- **[OpenCode](https://opencode.ai)** — Agentic coding with file editing, bash, grep, and MCP tools
- **[Claude Code](https://claude.ai/code)** — Anthropic's CLI (works with local models via Ollama API)
- **[OpenClaw](https://docs.ollama.com)** — Telegram bot bridge to your local model
- **[Open WebUI](https://github.com/open-webui/open-webui)** — Chat interface in the browser
- **[AnythingLLM](https://anythingllm.com)** — Enterprise RAG platform (cloud server)

---

## Quick Start

```bash
# One-command setup (WSL Kali, WSL Ubuntu, or native Linux)
bash scripts/setup.sh
```

This installs CUDA, builds llama.cpp (mainline + TurboQuant), installs OpenCode, and generates config files. See [scripts/setup.sh](scripts/setup.sh) for details.

**Manual quick start:**
```bash
# Start the server (pick your model)
./scripts/start-server.sh qwen  YOUR_MODEL_PATH/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf
./scripts/start-server.sh gemma YOUR_MODEL_PATH/gemma-4-31b-it-UD-Q4_K_XL.gguf
./scripts/start-server.sh turbo YOUR_MODEL_PATH/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf

# Start coding
cd your-project && opencode
```

---

## Hardware & Models

| Component | Details |
|---|---|
| GPU | NVIDIA RTX 5090 (32GB GDDR7, Blackwell) |
| OS | Windows 11 + WSL2 Kali Linux |
| Runtime | llama.cpp (compiled natively on WSL with CUDA) |

### Model Comparison

| | Qwen3.5-35B-A3B | Gemma 4 31B |
|---|---|---|
| **Architecture** | MoE (256 experts, 8 active) | Dense (all params active) |
| **Active params** | ~3B per token | 31B per token |
| **Quantization** | Unsloth UD-Q4_K_XL (20.7 GB) | Unsloth UD-Q4_K_XL (~18.4 GB) |
| **Generation** | **188 t/s** | 61 t/s |
| **Prompt processing** | **4,291 t/s** | 1,954 t/s |
| **KV cache (131K)** | 2.5 GB | 11.4 GB |
| **Total VRAM (131K)** | ~24 GB | ~29.8 GB |
| **Training context** | 262K | 131K |
| **TurboQuant** | Yes (turbo3) | Not tested |
| **Best for** | Fast agentic coding, iteration | Quality-critical tasks, reasoning |
| **First-shot quality** | Good (may need fixes) | Excellent (Asteroids: zero bugs) |

---

## Performance Benchmarks

### Speed Comparison (RTX 5090)

```
┌─────────────────────────────────────────────────────┐
│   Prompt Processing (tokens/s)                      │
│                                                     │
│   Qwen3.5 TurboQuant ██████████████   5,623         │
│   Qwen3.5 Mainline   ███████████     4,291          │
│   Gemma 4 Mainline   ████████        1,954          │
│                                                     │
│   Token Generation (tokens/s)                       │
│                                                     │
│   Qwen3.5 Mainline   ██████████████████████  188    │
│   Qwen3.5 TurboQuant ██████████████          131    │
│   Gemma 4 Mainline   ███████                  61    │
└─────────────────────────────────────────────────────┘
```

### VRAM Usage (131K Context)

```
┌──────────────────────────────────────────────────────────┐
│                    VRAM Breakdown (GB)                     │
│                                                          │
│   Qwen3.5 (f16 KV):                                     │
│   ├─ Model      ████████████████████░░░░░░  20.7 GB     │
│   ├─ KV Cache   ██░░░░░░░░░░░░░░░░░░░░░░░   2.5 GB     │
│   ├─ Compute    █░░░░░░░░░░░░░░░░░░░░░░░░░   0.8 GB     │
│   └─ Free       ██████░░░░░░░░░░░░░░░░░░░░   6.0 GB     │
│                                                          │
│   Qwen3.5 (turbo3 KV):                                  │
│   ├─ Model      ████████████████████░░░░░░  20.7 GB     │
│   ├─ KV Cache   █░░░░░░░░░░░░░░░░░░░░░░░░░  0.7 GB     │
│   ├─ Compute    █░░░░░░░░░░░░░░░░░░░░░░░░░   0.8 GB     │
│   └─ Free       ████████░░░░░░░░░░░░░░░░░░   8.4 GB     │
│                                                          │
│   Gemma 4 (f16 KV):                                     │
│   ├─ Model      ██████████████████░░░░░░░░  18.4 GB     │
│   ├─ KV Cache   ██████████░░░░░░░░░░░░░░░░  11.4 GB     │
│   ├─ Compute    █░░░░░░░░░░░░░░░░░░░░░░░░░   0.8 GB     │
│   └─ Free       ██░░░░░░░░░░░░░░░░░░░░░░░░   2.8 GB     │
│                                                          │
│   KV Cache Comparison:                                   │
│   Qwen3.5 f16:    2.5 GB  (MoE — only 1/4 layers)      │
│   Qwen3.5 turbo3: 0.7 GB  (3.5x compression)           │
│   Gemma 4 f16:   11.4 GB  (dense — all layers)          │
└──────────────────────────────────────────────────────────┘
```

### TurboQuant vs Standard KV Cache Quality

Based on the [TurboQuant CUDA fork](https://github.com/Madreag/turbo3-cuda) benchmarks on Qwen3.5-27B:

```
┌────────────────────────────────────────────────────┐
│         Perplexity (Lower = Better)                │
│                                                    │
│   q8_0 baseline  ████████████████████  5.8375      │
│   turbo3 uniform █████████████████████ 5.8323 ~    │
│   turbo3 LA-1    ████████████████████  5.7690 ++   │
│                                                    │
│   ~  = matches baseline                            │
│   ++ = BEATS baseline (-1.17%)                     │
│                                                    │
│   FWHT rotation: essential (+6.8% PPL without)     │
│   Norm correction: critical (+12% PPL without)     │
└────────────────────────────────────────────────────┘
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        WINDOWS 11                                │
│  ┌─────────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │  Desktop        │  │  Open WebUI  │  │  Brave Browser     │  │
│  │  Shortcuts      │  │  :5762       │  │  (Dashboard/Chat)  │  │
│  │  Start/Stop/    │  │  Docker      │  │                    │  │
│  │  Update         │  └──────┬───────┘  └────────────────────┘  │
│  └────────┬────────┘         │                                   │
│           │            host.docker.internal:10500                 │
│           ▼                  │                                   │
│  ┌───────────────────────────┴──────────────────────────────┐   │
│  │                    WSL2 KALI LINUX                        │   │
│  │                                                           │   │
│  │  ┌─────────────────────────────────────────────────────┐  │   │
│  │  │  llama-server (port 10500, 0.0.0.0)                 │  │   │
│  │  │  ├─ Model A: Qwen3.5-35B-A3B (MoE, 188 t/s)       │  │   │
│  │  │  ├─ Model B: Gemma 4 31B (Dense, 61 t/s)           │  │   │
│  │  │  ├─ Mode 1: f16 KV cache (mainline build)          │  │   │
│  │  │  └─ Mode 2: turbo3 KV cache (TurboQuant, Qwen only)│  │   │
│  │  └──────────────────────┬──────────────────────────────┘  │   │
│  │                         │ localhost:10500                  │   │
│  │  ┌──────────┐  ┌───────┴────┐  ┌───────────┐             │   │
│  │  │ OpenCode │  │ Claude Code│  │ OpenClaw   │             │   │
│  │  │ +Context7│  │ (claude-   │  │ (Telegram  │             │   │
│  │  │ +Chrome  │  │  qwen)     │  │  bot)      │             │   │
│  │  │  DevTools│  │            │  │            │             │   │
│  │  └──────────┘  └────────────┘  └───────────┘             │   │
│  │                                                           │   │
│  │  GPU: RTX 5090 (32GB) via CUDA passthrough                │   │
│  └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Model Selection Flow

```
What's your priority?
  │
  ├─ Best local coding (recommended) ──────> Qwen3.6-35B-A3B + TheTom TurboQuant turbo3
  │                                           (177 t/s, 262K ctx, native tool calls)
  │
  ├─ Legacy fast agentic coding ────────────> Qwen3.5-35B-A3B (188 t/s)
  │   └─ Save VRAM? ────────────────────────> Qwen3.5 + TurboQuant (131 t/s, 3.5x KV savings)
  │
  └─ Quality / Reasoning ───────────────────> Gemma 4 31B (61 t/s)
      └─ 24GB GPU? ─────────────────────────> Gemma 4 at 32-64K context
```

### Qwen3.6 Setup (Local RTX 5090)

1. Download `unsloth/Qwen3.6-35B-A3B-GGUF` → `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` (21GB)
2. Build TheTom's TurboQuant fork (required for Gated DeltaNet arch):
   ```bash
   git clone --depth 1 -b feature/turboquant-kv-cache \
     https://github.com/TheTom/llama-cpp-turboquant.git ~/llama-cpp-turboquant
   cd ~/llama-cpp-turboquant
   cmake -B build -DGGML_CUDA=ON -DGGML_NATIVE=ON -DGGML_CUDA_FA=ON \
     -DGGML_CUDA_FA_ALL_QUANTS=ON -DCMAKE_CUDA_ARCHITECTURES=120
   cmake --build build -j$(nproc)
   ```
3. Launch (single slot, full 262K context, turbo3 KV):
   ```bash
   TURBO_LAYER_ADAPTIVE=2 ~/llama-cpp-turboquant/build/bin/llama-server \
     -m /path/to/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
     -ngl 99 -fa on -c 262144 -np 1 -ctk turbo3 -ctv turbo3 \
     --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \
     --host 0.0.0.0 --port 10500
   ```
4. VRAM usage: ~25GB of 32GB (includes 262K turbo3 KV — only 10 layers have full KV thanks to hybrid arch)

---

## GPU Compatibility

| GPU | VRAM | Qwen3.5 Max Context | Gemma 4 Max Context | Notes |
|---|---|---|---|---|
| RTX 5090 | 32 GB | 131K (f16) / 262K (turbo3) | 131K | Full performance |
| RTX 4090 | 24 GB | ~96K (f16) / ~192K (turbo3) | ~32-64K | Reduce context for Gemma 4 |
| RTX 3090 | 24 GB | ~96K (f16) / ~192K (turbo3) | ~32-64K | Slightly slower than 4090 |
| RTX 4080 Super | 16 GB | ~32K (f16) | Not recommended | Use smaller quants |
| M4 Max | 64 GB | 262K | 131K+ | Use MLX for best speed |

For 16GB GPUs, consider smaller quants (Q3_K_M) or the Qwen3.5-27B variant.

---

## Setup Guide

### Prerequisites
- Windows 11 with WSL2 (or native Linux)
- NVIDIA GPU with CUDA support (tested on RTX 5090)
- WSL2 with Kali Linux or Ubuntu

### Automated Setup (Recommended)

```bash
git clone https://github.com/jamesarslan/local-ai-coding-setup.git
cd local-ai-coding-setup
bash scripts/setup.sh
```

The setup script handles everything: CUDA toolkit, llama.cpp builds, Node.js, OpenCode, and config generation.

### Manual Setup

#### 1. Install CUDA Toolkit (WSL)

```bash
sudo apt install -y cmake g++ git

# Ubuntu WSL:
wget -qO - https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/3bf863cc.pub \
    | sudo gpg --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/ /" \
    | sudo tee /etc/apt/sources.list.d/cuda-wsl.list

# Kali WSL (GPG workaround — Kali lacks NVIDIA's GPG key):
echo "deb [trusted=yes] https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/ /" \
    | sudo tee /etc/apt/sources.list.d/cuda-wsl.list

sudo apt update && sudo apt install -y cuda-toolkit
```

#### 2. Build llama.cpp

```bash
# Auto-detect your GPU architecture
CUDA_ARCH=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '.')
echo "GPU architecture: sm_${CUDA_ARCH}"

# Build mainline
git clone --depth 1 https://github.com/ggml-org/llama.cpp.git ~/llama-cpp-mainline
cd ~/llama-cpp-mainline
cmake -B build -DGGML_CUDA=ON -DGGML_NATIVE=ON -DGGML_CUDA_FA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"
cmake --build build -j$(nproc)

# Build TurboQuant fork (optional, for Qwen3.5 turbo3 mode)
# Madreag's fork: +13-69% faster at 32K vs base, SM86/89/120 optimized
git clone --depth 1 \
    https://github.com/Madreag/turbo3-cuda.git ~/llama-cpp-turboquant
cd ~/llama-cpp-turboquant
cmake -B build -DGGML_CUDA=ON -DGGML_NATIVE=ON -DGGML_CUDA_FA=ON \
    -DGGML_CUDA_FA_ALL_QUANTS=ON -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH"
cmake --build build -j$(nproc)
```

#### 3. Download Models

| Model | Link | Size |
|---|---|---|
| Qwen3.5-35B-A3B | [Unsloth GGUF](https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF) — get `UD-Q4_K_XL` | 20.7 GB |
| Gemma 4 31B IT | [Unsloth GGUF](https://huggingface.co/unsloth/gemma-4-31b-it-GGUF) — get `UD-Q4_K_XL` | ~18.4 GB |

#### 4. Start the Server

```bash
# Qwen3.5 (fast, agentic coding)
./scripts/start-server.sh qwen YOUR_MODEL_PATH/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf

# Gemma 4 (quality, reasoning)
./scripts/start-server.sh gemma YOUR_MODEL_PATH/gemma-4-31b-it-UD-Q4_K_XL.gguf

# Qwen3.5 + TurboQuant (3.5x KV compression)
./scripts/start-server.sh turbo YOUR_MODEL_PATH/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf
```

#### 5. Configure OpenCode

Copy `configs/opencode.json` to `~/.config/opencode/opencode.json`. Replace `YOUR_PORT` with `10500` (default).

Both models are pre-configured — switch between them by changing the `"model"` field:
- `"llama.cpp/qwen3.5-coding"` for speed
- `"llama.cpp/gemma-4-31B"` for quality

#### 6. Start Coding

```bash
cd your-project && opencode
```

### Linux Setup (No WSL)

Same as steps 2-6 above. Skip WSL-specific CUDA repo setup — use the repo for your distro.

### Windows-Only Setup (No WSL)

1. Download prebuilt llama.cpp from [GitHub Releases](https://github.com/ggml-org/llama.cpp/releases) — get `llama-b{version}-bin-win-cuda-{ver}-x64.zip`
2. Download matching `cudart-llama-bin-win-cuda-{ver}-x64.zip`
3. Extract both, copy DLLs next to `llama-server.exe`
4. Run: `llama-server.exe -m model.gguf -ngl 99 -fa on -c 131072 --host 0.0.0.0 --port 10500`
5. Note: TurboQuant fork requires building from source (needs Visual Studio + CUDA Toolkit)

### Mac (Apple Silicon)

Use [MLX](https://github.com/ml-explore/mlx) instead of llama.cpp for best performance. TurboQuant has an [MLX implementation](https://github.com/Blaizzy/mlx-vlm/pull/858).

---

## Optimal Model Parameters

### Qwen3.5 (Coding)

From the [official Qwen3.5 documentation](https://huggingface.co/Qwen/Qwen3.5-35B-A3B):

| Mode | temp | top_p | top_k | min_p | presence_penalty |
|---|---|---|---|---|---|
| **Coding (thinking)** | 0.6 | 0.95 | 20 | 0.0 | 0.0 |
| General (thinking) | 1.0 | 0.95 | 20 | 0.0 | 1.5 |
| Instruct (no thinking) | 0.7 | 0.8 | 20 | 0.0 | 1.5 |

### Gemma 4 31B

| Parameter | Value | Notes |
|---|---|---|
| temperature | 1.0 | Trained with temp=1.0 (unlike Qwen3.5's 0.6) |
| top_k | 64 | Higher than Qwen3.5's 20 |
| top_p | 0.95 | Standard |
| min_p | 0.0 | Standard |

> **Critical finding:** Ollama's default parameters for Qwen3.5 were `temperature=1.0` and `presence_penalty=1.5` — both wrong for coding tasks. This alone caused noticeably worse output quality. Gemma 4 works fine at temp=1.0 because it was trained that way.

---

## What is TurboQuant?

[TurboQuant](https://research.google/blog/turboquant-redefining-ai-efficiency-with-extreme-compression/) (Google Research, ICLR 2026) is a KV cache compression algorithm that achieves **3.5x compression with zero accuracy loss**. Currently available for **Qwen3.5 only** (not tested with Gemma 4).

### How it works:

1. **PolarQuant** — Randomly rotates data vectors using FWHT, then quantizes in polar coordinates. This eliminates the per-block normalization overhead that traditional quantization requires.

2. **QJL (Quantized Johnson-Lindenstrauss)** — Uses 1 bit per residual to correct errors from step 1. Acts as a mathematical error-checker with zero memory overhead.

3. **The result**: 3.25-bit KV cache (`turbo3`) that actually **beats 8-bit** quality because the rotation + correction approach preserves vector relationships better than naive per-block scaling.

### Why this matters for local inference:

```
Qwen3.5 without TurboQuant (f16 KV):
  32GB VRAM = 20.7GB model + 2.5GB KV cache + overhead
  -> 131K context max, 6.0GB free

Qwen3.5 with TurboQuant (turbo3 KV):
  32GB VRAM = 20.7GB model + 0.7GB KV cache + overhead
  -> 131K context with 8.4GB free
  -> Or 262K context (full training length) possible

Gemma 4 without TurboQuant (f16 KV):
  32GB VRAM = 18.4GB model + 11.4GB KV cache + overhead
  -> 131K context, only 2.8GB free (tight!)
  -> turbo3 would save ~8GB if compatible (untested)
```

### CUDA Implementation

We use the [community CUDA port](https://github.com/Madreag/turbo3-cuda) which adds:
- Custom Flash Attention kernels for turbo3 K/V operations
- Tensor-core prefill path (MMA acceleration)
- Layer-adaptive mode preserving critical layers at q8_0
- Tested on RTX 3090 and RTX 5090

---

## Tool Ecosystem

### OpenCode (Primary — Agentic Coding)

Best tool for local models. Lean tool set (read, write, edit, bash, grep, glob) doesn't bloat the context like Claude Code's dozens of MCP tools.

**MCP Servers:**
- **Context7** — Documentation search. Add `use context7` to prompts to look up API docs.
- **Chrome DevTools** — Browser verification. Auto-launches Chromium, inspects pages, runs console JS, takes screenshots.

**Model selection in OpenCode:** Both Qwen3.5 and Gemma 4 are configured. Change `"model"` in opencode.json:
- `"llama.cpp/qwen3.5-coding"` for speed (agentic workflows)
- `"llama.cpp/gemma-4-31B"` for quality (single-shot generation)

### Claude Code (Anthropic API + Local Model Fallback)

Works with local models via `claude-qwen` bash function, but sends ALL connected MCP tool schemas (Notion, Slack, Atlassian, etc.) which taxes local models heavily. Best used with Anthropic's cloud API.

### OpenClaw (Telegram Bot)

Bridges Telegram to your local model via native Ollama API. Configure with `api: "openai-completions"` for llama-server.

### Open WebUI (Chat Interface)

Docker container on port 5762, connects to llama-server via `host.docker.internal:10500` (WSL) or `172.17.0.1:10500` (native Linux).

---

## Key Findings & Lessons Learned

### 1. Model choice matters: MoE vs Dense
Qwen3.5 (MoE, 3B active) is 3x faster than Gemma 4 (dense, 31B active), but Gemma 4 produces higher quality first-shot output. The Asteroids test showed this clearly: Gemma 4 produced a bug-free game on first try, while Qwen3.5 needed minor fixes. For agentic coding with many iterations, Qwen3.5's speed advantage wins. For quality-critical single-shot generation, Gemma 4 is better.

### 2. Tool count matters more than you think
> *"Swapped from 11 tools to 5. Same model, same hardware. Response time went from ~5 min to ~1 min."* — Reddit user

Claude Code sends dozens of MCP tool schemas. OpenCode sends ~10. For local models, use OpenCode. This applies equally to both Qwen3.5 and Gemma 4.

### 3. Ollama's default parameters are wrong for Qwen3.5 coding
Ollama ships Qwen3.5 with `temperature=1.0` and `presence_penalty=1.5`. The official recommendation for coding is `temp=0.6, presence_penalty=0.0`. Gemma 4 works correctly at temp=1.0 — each model needs different parameters.

### 4. Unsloth UD GGUFs don't work with Ollama
Ollama 0.18.2 on Windows can't load Unsloth's HuggingFace GGUFs. llama-server loads them fine. If using Ollama, stick with registry models.

### 5. KV cache quantization sensitivity varies by model
Standard q8_0 KV cache quantization degrades Qwen3.5 quality at 20-40K+ context. TurboQuant's approach (FWHT rotation + norm correction) doesn't have this problem — it actually improves quality.

### 6. Dense models eat VRAM for KV cache
Gemma 4's 11.4GB KV cache at 131K (vs Qwen3.5's 2.5GB) is the primary constraint on 32GB GPUs. Its SWA layers also break prompt caching, which hurts agentic workloads where the system prompt repeats across many requests.

### 7. WSL2 is better than Windows for llama.cpp
- Native Linux build is faster to compile
- Direct GPU passthrough works seamlessly
- No Windows PATH issues breaking bash scripts
- Compatible with research forks that only support Linux builds

### 8. Chrome DevTools MCP needs the right flags
`--executablePath /usr/bin/chromium --chromeArg --no-sandbox` for auto-launch. The `--cdp-url` and `--browserUrl` flags are for connecting to an existing instance.

---

## Desktop Shortcuts (Windows)

| Shortcut | What it does |
|---|---|
| Start Qwen AI Server | WSL llama-server with Qwen3.5, f16 KV cache |
| Start Qwen AI TurboQuant | WSL llama-server with Qwen3.5, turbo3 KV cache |
| Stop Qwen AI Server | Kills llama-server in WSL |
| Update Qwen AI Server | Downloads latest llama.cpp Windows prebuilt |

---

## Repository Contents

```
local-ai-coding-setup/
├── README.md                              # This file
├── scripts/
│   ├── setup.sh                           # One-command setup (CUDA, llama.cpp, OpenCode)
│   └── start-server.sh                    # Start llama-server (qwen|gemma|turbo modes)
├── configs/
│   ├── opencode.json                      # OpenCode config (Qwen3.5 + Gemma 4)
│   ├── openclaw.json                      # OpenClaw/Telegram bot config
│   ├── claude-code-bashrc.sh              # Claude Code bash function
│   ├── open-webui-docker.sh               # Open WebUI Docker run command
│   └── ollama-modelfile                   # Ollama Modelfile with correct params
└── research/
    ├── gemma4-findings.md                 # Gemma 4 31B benchmarks & analysis
    ├── turboquant-findings.md             # TurboQuant benchmarks & analysis
    ├── qwen35-parameter-tuning.md         # Optimal parameters for both models
    ├── tool-ecosystem-comparison.md       # OpenCode vs Claude Code vs OpenClaw
    └── test-prompts.md                    # Ready-to-use test prompts with results
```

---

## Cloud Server Setup (Optional — RTX PRO 6000 96GB)

For heavier models and enterprise use cases, deploy on a cloud GPU server.

### Components

| Service | Port | Description |
|---|---|---|
| **llama-server** | 8000 | Bearer-auth protected inference endpoint |
| **Extract API** | 8001 | Structured data extraction (text or PDF → JSON) |
| **Mistral OCR MCP** | 8002 | PDF → markdown-text extraction via Mistral API, as MCP tool for AnythingLLM |
| **AnythingLLM** | 3001 | RAG workspace with embedded LanceDB, Docker |

### Recommended Cloud Model: Gemma 4 26B-A4B

- **Architecture:** MoE (26B total, 4B active per token, 256 experts with 8 routed + 1 shared)
- **Quantization:** Unsloth Q8_0 (26.9GB, re-uploaded April 2026 with fixed tool-call tokenizer)
- **Context:** 262K native
- **VRAM:** ~30.5GB loaded with 4 parallel slots at 262K ctx — leaves 65GB+ headroom
- **Why Gemma 4 on the cloud:** Native function calling trained in. Qwen3.5-122B is an impressive chat model but its 10B active MoE can't reliably emit tool-call JSON in AnythingLLM's agent loop. Gemma 4 26B-A4B's trained `<|tool_call>` delimiters make it the reliable choice for `@agent` mode.

### Alternative: Qwen3.5-122B-A10B for Chat/Reasoning

If you want the biggest reasoner on the same hardware:
- **Quantization:** Unsloth UD-Q4_K_XL (72GB) — latest version with fixed chat template
- **VRAM:** ~73GB model + ~4GB KV (turbo3, 131K ctx × 2 slots) = ~77GB of 96GB
- Skip this for agent/tool workloads — it loops or refuses under AnythingLLM's agent schema
- bartowski Q4_K_M is **broken** — infinite-thinking loop on even simple prompts due to an older chat template. Always use Unsloth UD-Q4_K_XL or later.

### TurboQuant on the Cloud Box

[Madreag's CUDA fork](https://github.com/Madreag/turbo3-cuda) for classic transformer/MoE architectures:
- turbo3 KV (5.12x compression, 3.125 bits/value)
- TURBO_LAYER_ADAPTIVE=2 (closes 40% of turbo3-to-q8_0 PPL gap)
- SM120 optimized (Blackwell server-class cards)
- Sparse V skip enabled (zero quality cost, +4.6% speed at 32K)

```bash
# Example: Qwen3.5-122B with Madreag TurboQuant
TURBO_LAYER_ADAPTIVE=2 llama-server \
    -m Qwen3.5-122B-A10B-UD-Q4_K_XL.gguf \
    -ngl 99 -fa on -c 131072 -np 2 \
    -ctk turbo3 -ctv turbo3 \
    --temp 0.6 --top-k 20 --min-p 0.0 \
    --host 0.0.0.0 --port 8000 \
    --api-key $YOUR_BEARER_TOKEN
```

For **Qwen3.6-35B-A3B** (Gated DeltaNet hybrid) use [TheTom's fork](https://github.com/TheTom/llama-cpp-turboquant) instead — it's the only fork with `LLM_ARCH_QWEN3NEXT` support for the SSM state tensors.

### systemd + JSON-args gotcha

`ExecStart=... --chat-template-kwargs '{"enable_thinking":false}'` fails — systemd strips the `"` characters before llama-server sees them. Wrap in a shell script:

```bash
# /home/user/start-llama.sh
#!/bin/bash
export TURBO_LAYER_ADAPTIVE=2
exec /home/user/llama-cpp-turboquant/build/bin/llama-server \
    -m /path/to/model.gguf \
    -ngl 99 -fa on -c 131072 -np 2 -ctk turbo3 -ctv turbo3 \
    --host 0.0.0.0 --port 8000 \
    --api-key $TOKEN
```
Then `ExecStart=/home/user/start-llama.sh` in the systemd unit — shell quoting preserves everything.

### Thinking Mode Control

Keep the server's **default** thinking mode ON (it's required for proper agentic coding). Disable per-request in the extract API only:

```json
{
  "model": "...",
  "messages": [...],
  "temperature": 0,
  "chat_template_kwargs": {"enable_thinking": false}
}
```

Qwen3.5-122B can waste 3000+ tokens just thinking about "hello" with default settings — always set `enable_thinking: false` for extraction endpoints.

### Mistral OCR MCP Server

A lightweight MCP server that exposes Mistral's OCR API as AnythingLLM tools:

```
PDF upload → Mistral OCR API → markdown text → Agent applies custom prompts
```

Configured in AnythingLLM's `anythingllm_mcp_servers.json`:
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

See `configs/mistral-ocr-mcp.py` for a drop-in FastMCP server template.

### Extract API Pipeline

```
PDF → Mistral OCR (markdown text) → LLM (schema-driven extraction) → Clean JSON
```

The extract API exposes `/extract` for plain text and `/extract-pdf` for PDF bytes. The system prompt defines the target JSON schema — swap it to match your domain (contracts, invoices, medical forms, or anything else). See `configs/extract-api.py` for a template.

---

## Links & Resources

### Models
| Resource | Link |
|---|---|
| Qwen3.5-35B-A3B (base) | https://huggingface.co/Qwen/Qwen3.5-35B-A3B |
| Qwen3.5-122B-A10B (base) | https://huggingface.co/Qwen/Qwen3.5-122B-A10B |
| Qwen3.5-122B bartowski GGUF (recommended for TurboQuant) | https://huggingface.co/bartowski/Qwen_Qwen3.5-122B-A10B-GGUF |
| Qwen3.5-35B Unsloth GGUF quants | https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF |
| Gemma 4 31B IT (base) | https://huggingface.co/google/gemma-4-31b-it |
| Gemma 4 Unsloth GGUF quants | https://huggingface.co/unsloth/gemma-4-31b-it-GGUF |
| Qwen3.5 blog post | https://qwen.ai/blog?id=qwen3.5 |
| Unsloth (quantization tools) | https://github.com/unslothai/unsloth |

### Inference Engine
| Resource | Link |
|---|---|
| llama.cpp (mainline) | https://github.com/ggml-org/llama.cpp |
| llama.cpp releases (prebuilt) | https://github.com/ggml-org/llama.cpp/releases |
| TurboQuant CUDA fork (TheTom — has Qwen3NEXT for Qwen3.6 Gated DeltaNet) | https://github.com/TheTom/llama-cpp-turboquant |
| TurboQuant CUDA fork (Madreag — fastest decode at 32K on SM120) | https://github.com/Madreag/turbo3-cuda |
| TurboQuant CUDA fork (spiritbuun, original) | https://github.com/spiritbuun/llama-cpp-turboquant-cuda |

### Research
| Resource | Link |
|---|---|
| TurboQuant paper (Google, ICLR 2026) | https://research.google/blog/turboquant-redefining-ai-efficiency-with-extreme-compression/ |
| TurboQuant MLX implementation | https://github.com/Blaizzy/mlx-vlm/pull/858 |
| QJL paper | https://arxiv.org/abs/2402.09078 |
| PolarQuant paper (AISTATS 2026) | Referenced in TurboQuant blog |

### Tools
| Tool | Link | What it does |
|---|---|---|
| OpenCode | https://opencode.ai / https://github.com/opencode-ai/opencode | Agentic coding (recommended for local models) |
| Claude Code | https://claude.ai/code / https://github.com/anthropics/claude-code | Anthropic's coding CLI |
| OpenClaw | https://docs.ollama.com | Telegram/messaging bot bridge |
| Open WebUI | https://github.com/open-webui/open-webui | Browser chat interface |
| Context7 MCP | https://context7.com | Documentation search |
| Chrome DevTools MCP | https://github.com/anthropics/anthropic-cookbook | Browser automation |
| Ollama | https://ollama.com | Local model runner (alternative to llama-server) |
| AnythingLLM | https://anythingllm.com | RAG knowledge base platform |
| Mistral OCR API | https://docs.mistral.ai/capabilities/document_ai | PDF text extraction |

### Community
| Resource | Link |
|---|---|
| r/LocalLLaMA (Reddit) | https://reddit.com/r/LocalLLaMA |

---

## License

MIT — Use however you want. If you build on this, share your findings!

---

## Author

Built and maintained by [James Arslan](https://github.com/jamesarslan). Tested on RTX 5090 (local) and RTX PRO 6000 96GB (cloud) with Qwen3.5/3.6, Gemma 4 26B/31B, and TurboQuant KV compression.
