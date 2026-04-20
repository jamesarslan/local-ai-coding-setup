# Gemma 4 31B Research Findings

## Model Details

- **Model**: [Google Gemma 4 31B IT](https://huggingface.co/google/gemma-4-31b-it)
- **Architecture**: Dense transformer, all 31B parameters active per token
- **Quantization**: [Unsloth UD-Q4_K_XL](https://huggingface.co/unsloth/gemma-4-31b-it-GGUF) (~18.4 GB)
- **Attention**: Hybrid — full attention + Sliding Window Attention (SWA, 4096 tokens)
- **Runtime**: llama.cpp (mainline, compiled with CUDA on WSL Kali)

## Benchmark Results (RTX 5090, 131K Context)

### Speed

| Metric | Gemma 4 31B | Qwen3.5-35B-A3B | Ratio |
|---|---|---|---|
| Token generation | 61 t/s | 188 t/s | 3.1x slower |
| Prompt processing | 1,954 t/s | 4,291 t/s | 2.2x slower |

The speed difference is entirely due to architecture: Gemma 4 activates all 31B parameters per token, while Qwen3.5's MoE only activates ~3B. For interactive coding, 61 t/s is still fast enough — you won't be waiting. For agentic workflows with many back-and-forth tool calls, the 3x speed difference adds up.

### VRAM Usage (131K Context)

| Component | Gemma 4 31B | Qwen3.5-35B-A3B |
|---|---|---|
| Model weights | ~18,400 MiB | ~20,686 MiB |
| KV cache (f16) | ~11,400 MiB | ~2,560 MiB |
| Compute buffers | ~757 MiB | ~757 MiB |
| **Total** | **~29,800 MiB** | **~24,000 MiB** |
| Free VRAM | ~2,800 MiB | ~6,100 MiB |

Gemma 4's KV cache is 4.5x larger than Qwen3.5's because it's a dense model — every layer contributes to the KV cache. At 131K context, this leaves only ~2.8GB free on a 32GB card, making it tight but workable.

### KV Cache Breakdown

The 11.4GB KV cache splits into two types due to Gemma 4's hybrid attention:

| Component | Size | Layers |
|---|---|---|
| Global attention KV | ~10.2 GB | Full-context attention layers |
| SWA (Sliding Window) KV | ~1.2 GB | 4096-token window layers |
| **Total** | **~11.4 GB** | All layers |

### SWA Breaks Prompt Caching

Gemma 4's Sliding Window Attention layers only attend to the last 4096 tokens. This means:

- **Prompt caching does not work properly** — SWA layers discard older tokens, so cached KV entries become stale when new tokens shift the window
- Each new request effectively reprocesses through SWA layers, even if the prompt prefix is identical
- This does NOT affect quality — SWA is by design, the model was trained with it
- It DOES affect throughput for agentic workloads where the system prompt is the same across many requests

For agentic coding (many tool calls with the same system prompt), Qwen3.5 is faster both in raw speed AND in effective prompt caching.

## Code Quality: Asteroids Test

The Asteroids arcade clone prompt (see `test-prompts.md` Test 1) is our standard first-shot quality test.

### Gemma 4 Result
- **Worked perfectly on first try** — no bugs, no fixes needed
- Clean OOP structure, proper physics, correct screen wrapping
- All game mechanics (thrust, rotation, shooting, asteroid splitting, scoring) correct
- Pygame usage was idiomatic and efficient

### Qwen3.5 Result (for comparison)
- Worked on first try but needed minor fixes:
  - Screen wrapping had edge cases with large asteroids
  - Bullet cleanup was missing (bullets persisted after leaving screen bounds in some cases)
- Fixed with a single follow-up prompt

### Conclusion
Gemma 4 produced higher quality output on this test. The dense architecture (31B active vs 3B active) gives it more reasoning capacity per token, which shows in code correctness.

## TurboQuant Compatibility

TurboQuant (`turbo3` KV cache compression) is currently available for **Qwen3.5 only**. It has not been tested with Gemma 4's hybrid attention architecture, and the SWA layers may require special handling for KV cache compression.

## Recommended Sampling Parameters

From testing and community findings:

| Parameter | Gemma 4 31B | Notes |
|---|---|---|
| temperature | 1.0 | Gemma 4 was trained with temp=1.0 |
| top_k | 64 | Higher than Qwen3.5's 20 |
| top_p | 0.95 | Standard |
| min_p | 0.0 | Standard |

Unlike Qwen3.5 where `temp=0.6` is critical for coding, Gemma 4 performs well at `temp=1.0` because its training distribution already accounts for this temperature.

## When to Use Each Model

| Scenario | Best Model | Why |
|---|---|---|
| Agentic coding (many tool calls) | Qwen3.5 | 3x faster, prompt caching works |
| Single-shot code generation | Gemma 4 | Better first-try quality |
| Complex reasoning tasks | Gemma 4 | 31B active params vs 3B |
| Long context processing | Qwen3.5 | 4.5x less KV cache, more headroom |
| Quality-critical output | Gemma 4 | Fewer bugs, more polished code |
| Fast iteration/prototyping | Qwen3.5 | 188 t/s makes feedback loops tight |
| VRAM-constrained (24GB GPUs) | Qwen3.5 | Gemma 4 may not fit at high context |

## Download

- **Unsloth GGUF**: https://huggingface.co/unsloth/gemma-4-31b-it-GGUF
- **Recommended quant**: `UD-Q4_K_XL` (~18.4 GB, fits 32GB GPU with 131K context)
- **For 24GB GPUs**: Use `Q4_K_M` with reduced context (~32-64K)
