# TurboQuant Research Findings

## Source
- **Paper**: [TurboQuant: Redefining AI efficiency with extreme compression](https://research.google/blog/turboquant-redefining-ai-efficiency-with-extreme-compression/) (Google Research, ICLR 2026)
- **CUDA Forks** (all three tested, see comparison below):
  - [TheTom/llama-cpp-turboquant](https://github.com/TheTom/llama-cpp-turboquant) — **recommended for Qwen3.6+** (has `LLM_ARCH_QWEN3NEXT`)
  - [Madreag/turbo3-cuda](https://github.com/Madreag/turbo3-cuda) — fastest decode on SM120 for older arches
  - [spiritbuun/llama-cpp-turboquant-cuda](https://github.com/spiritbuun/llama-cpp-turboquant-cuda) — original, superseded
- **MLX Implementation**: [Blaizzy/mlx-vlm PR #858](https://github.com/Blaizzy/mlx-vlm/pull/858)

## Fork Comparison (April 2026)

| Fork | Fresh vs mainline | Qwen3NEXT/Gated DeltaNet | SM120 (5090) | Turbo Types | Decode @ 32K |
|---|---|---|---|---|---|
| **TheTom** (default feature/turboquant-kv-cache) | 54 commits behind | ✅ Has `LLM_ARCH_QWEN3NEXT` | ✅ | turbo2/3/4 + TCQ1S | baseline |
| **Madreag** (release/cuda-optimized) | 320 commits behind | ❌ No Qwen3NEXT | ✅ | turbo1.5/2/3/4 + TCQ | **+13-69% vs TheTom** |
| **spiritbuun** | Oldest | ❌ No Qwen3NEXT | ✅ | turbo3/4 | slowest |

### Choosing a Fork
- **Qwen3.6-35B-A3B (Gated DeltaNet hybrid)** → **TheTom** (other forks may refuse to load or miss state-space layers)
- **Qwen3.5 / classic transformer architectures** → **Madreag** (faster at 32K+ on SM120)
- **Don't build spiritbuun** unless reproducing legacy benchmarks

### Build Command (Both Forks, Blackwell SM120)
```bash
cmake -B build \
  -DGGML_CUDA=ON -DGGML_NATIVE=ON \
  -DGGML_CUDA_FA=ON -DGGML_CUDA_FA_ALL_QUANTS=ON \
  -DCMAKE_CUDA_ARCHITECTURES=120 \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

## What TurboQuant Does

Traditional KV cache quantization (q8_0, q4_0) uses simple per-block scaling to compress the key-value cache. This works for some models but causes quality degradation on others — notably Qwen3.5, which is sensitive to KV cache quantization at 20-40K+ context.

TurboQuant takes a fundamentally different approach:

### Step 1: PolarQuant (FWHT Rotation)
- Randomly rotates data vectors using Fast Walsh-Hadamard Transform (FWHT)
- Converts to polar coordinates, eliminating per-block normalization overhead
- The rotation makes value distributions near-uniform, which is ideal for quantization

### Step 2: QJL Sign Correction (1-bit residual)
- Uses Johnson-Lindenstrauss Transform to encode the quantization error
- Only 1 bit per residual — zero memory overhead
- Acts as a mathematical error-checker that eliminates bias in attention scores

### The Result
- `turbo3` = 3.25 bits per value (vs 16 bits for f16, 8 bits for q8_0)
- **Beats q8_0 quality** because the rotation preserves vector relationships
- 3.5-4.9x compression depending on layer-adaptive mode

## Our Benchmark Results — Qwen3.6-35B-A3B (RTX 5090, TheTom fork, UD-Q4_K_XL, April 2026)

Qwen3.6 ships with a hybrid architecture: 30 Gated DeltaNet (linear-attention) layers + 10 Gated Attention (full) layers, interleaved. Only the 10 full-attention layers carry a traditional KV cache — the DeltaNet layers have a small recurrent SSM state instead. This means TurboQuant's compression only acts on 1/4 of the layers, but the total KV cache is already tiny to begin with.

| Mode | Model size | VRAM at 262K ctx (1 slot) | Free VRAM | Gen speed |
|---|---|---|---|---|
| TheTom + turbo3 + TLA=2 | 21 GB | **25 GB** | ~7.6 GB | **177 t/s** |
| TheTom + turbo3 + tool calling | 21 GB | ~25 GB | ~7.6 GB | 162 t/s |

Tool calling worked on the first attempt — native `finish_reason: "tool_calls"` with clean JSON arguments. No infinite-thinking loop (unlike the Qwen3.5-122B MoE cloud test).

## Our Benchmark Results — Qwen3.5-35B-A3B (RTX 5090, spiritbuun legacy fork)

### VRAM Usage (131K Context)

| Mode | Model | KV Cache | Compute | Free | Total |
|---|---|---|---|---|---|
| f16 KV | 20,686 MiB | 2,560 MiB | 757 MiB | 6,100 MiB | 32,607 MiB |
| turbo3 KV | 20,686 MiB | ~730 MiB | 757 MiB | 8,430 MiB | 32,607 MiB |
| **Savings** | — | **1,830 MiB** | — | **+2,330 MiB** | — |

### Speed

| Mode | Prompt Processing | Token Generation |
|---|---|---|
| f16 KV (mainline) | 4,291 t/s | 188 t/s |
| turbo3 KV (TurboQuant) | 5,623 t/s | 131 t/s |

- Prompt processing is **31% faster** with turbo3 (likely due to smaller KV cache fitting better in GPU cache)
- Token generation is **30% slower** (structural: memory-bound decode with turbo3 dequant overhead)
- Net effect depends on workload: prompt-heavy tasks (agentic coding) benefit, chat-heavy tasks may be slower

### Quality (from TurboQuant fork benchmarks on Qwen3.5-27B)

| Config | Perplexity | vs q8_0 | KV Compression |
|---|---|---|---|
| q8_0 baseline | 5.8375 | — | 1.0x |
| turbo3 LA-1 | 5.7690 | **-1.17% better** | 3.5x |
| turbo3 uniform | 5.8323 | -0.09% (matched) | 4.9x |

## Critical Implementation Details

### FWHT Rotation is Essential
Without FWHT rotation: +6.8% perplexity degradation
This is why standard q4_0/q8_0 fails on some models — no rotation step.

### Norm Correction is Critical
Without norm correction: +12% perplexity degradation
turbo3 would be *worse* than q8_0 without it.

### Layer-Adaptive Mode
- `TURBO_LAYER_ADAPTIVE=1`: Best quality, preserves critical layers at q8_0 (~65K context)
- `TURBO_LAYER_ADAPTIVE=5`: Extended context (128K+), more layers compressed
- Unset: Maximum compression (4.9x), all layers turbo3

### Qwen3.5 Hybrid Architecture Consideration
Qwen3.5 uses Gated Delta Net (recurrent) + MoE (sparse), not pure transformer attention. TurboQuant's KV cache compression only applies to the attention layers (every 4th layer in Qwen3.5). The recurrent state is separate and not compressed.

## Model Compatibility

| Model | TurboQuant Support | Notes |
|---|---|---|
| **Qwen3.6-35B-A3B** | Yes (TheTom fork only) | Hybrid Gated DeltaNet + Gated Attention. Only 10 of 40 layers have full KV. Needs `LLM_ARCH_QWEN3NEXT` to register SSM state tensors correctly. 262K native context fits easily at 25GB total on 5090. |
| Qwen3.5-35B-A3B | Yes (all forks) | MoE architecture, small KV cache already, turbo3 saves additional ~1.8GB |
| **Qwen3.5-122B-A10B** | Yes (cloud tested, Madreag) | Classic MoE, no SSM layers, works with Madreag on SM120 96GB server. Infinite-thinking quirk is a chat-template issue, not a TurboQuant issue (see `research/cloud-server-findings.md`) |
| Gemma 4 31B | Not tested | Hybrid attention (global + SWA). Dense model with 11.4GB KV at 131K — would benefit most, but SWA + turbo3 interaction untested. |
| **Gemma 4 26B-A4B (MoE)** | Not tested yet | 4B active MoE, 256K native context. Native function calling works great without TurboQuant on cloud. Would likely also work — 30-layer MoE is close enough to Qwen3.5 shape. |
| Other models | Varies | Community forks primarily tested on Qwen3 family |

### Why Gemma 4 Would Benefit Most
Gemma 4's 11.4GB KV cache at 131K context is the biggest bottleneck on 32GB GPUs. If turbo3 achieves similar 3.5x compression, it would reduce KV cache to ~3.3GB, freeing ~8GB of VRAM. However, the SWA layers' sliding window behavior may interact unpredictably with TurboQuant's rotation-based quantization. Testing is needed.

## Comparison with Standard KV Cache Quantization

| Feature | q8_0 / q4_0 | TurboQuant turbo3 |
|---|---|---|
| Approach | Per-block scaling | FWHT rotation + polar quant + QJL |
| Bits per value | 8 / 4 | 3.25 |
| Memory overhead | 1-2 extra bits for scale factors | Zero (rotation eliminates normalization) |
| Quality vs f16 | Degrades at high context on sensitive models | Matches or beats q8_0 |
| Qwen3.5 compatible | Degrades at 20-40K+ tokens | Works well (tested to 128K) |
| Requires custom kernels | No (built into llama.cpp) | Yes (custom Flash Attention kernels) |
| Status in llama.cpp | Built-in | Community fork only |

## Future: When Will This Be in Mainline llama.cpp?

Not yet. The community CUDA port is a fork. Key blockers:
1. Needs upstream review and approval
2. May need architecture-specific tuning for different GPUs
3. Google's official implementation is in JAX only
4. The llama.cpp team may implement their own version differently

Watch the [llama.cpp issues](https://github.com/ggml-org/llama.cpp/issues) for TurboQuant/PolarQuant mentions.
