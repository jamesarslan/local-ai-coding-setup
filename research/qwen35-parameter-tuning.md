# Model Parameter Tuning Research

## Models Tested

### Qwen3.6-35B-A3B (PRIMARY — April 2026)
- **Model**: [Qwen/Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- **Quantization**: [unsloth/Qwen3.6-35B-A3B-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF) (UD-Q4_K_XL, 21 GB)
- **Architecture**: Hybrid — 30 × Gated DeltaNet (SSM) + 10 × Gated Attention (full), 256-expert MoE with 8 routed + 1 shared active
- **Active Parameters**: ~3B per token (out of 35B total)
- **Training Context**: 262,144 tokens (extensible to 1M)
- **Why it replaces 3.5**: Native tool calling with stable JSON generation, improved agentic coding benchmarks, developer-role support for OpenCode/Codex. Same 3B active footprint → same speed class, better output.

### Qwen3.5-35B-A3B (Legacy)
- **Model**: [Qwen/Qwen3.5-35B-A3B](https://huggingface.co/Qwen/Qwen3.5-35B-A3B)
- **Quantization**: [unsloth/Qwen3.5-35B-A3B-GGUF](https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF) (UD-Q4_K_XL variant)
- **Architecture**: Hybrid — Gated Delta Net (recurrent, 3/4 layers) + Gated Attention (1/4 layers) + MoE (256 experts, 8 active + 1 shared)
- **Active Parameters**: ~3B per token (out of 35B total)
- **Training Context**: 262,144 tokens

### Gemma 4 31B
- **Model**: [google/gemma-4-31b-it](https://huggingface.co/google/gemma-4-31b-it)
- **Quantization**: [unsloth/gemma-4-31b-it-GGUF](https://huggingface.co/unsloth/gemma-4-31b-it-GGUF) (UD-Q4_K_XL variant)
- **Architecture**: Dense transformer, all 31B parameters active per token
- **Attention**: Hybrid — full attention + Sliding Window Attention (SWA, 4096 tokens)
- **Training Context**: 131,072 tokens

## Optimal Parameters by Model

### Qwen3.6 — Official Recommended Parameters

From the [Qwen3.6 HuggingFace page](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) (same numbers as 3.5):

| Mode | temp | top_p | top_k | min_p | presence_penalty | repeat_penalty |
|---|---|---|---|---|---|---|
| **Thinking + Coding** | 0.6 | 0.95 | 20 | 0.0 | 0.0 | 1.0 |
| Thinking + General | 1.0 | 0.95 | 20 | 0.0 | 1.5 | 1.0 |
| Non-thinking + General | 0.7 | 0.8 | 20 | 0.0 | 1.5 | 1.0 |
| Non-thinking + Reasoning | 1.0 | 1.0 | 40 | 0.0 | 2.0 | 1.0 |

**Max output length**: 32,768 tokens for most tasks. 81,920 for math/code benchmarks.

### Qwen3.6 Thinking Control
Per-request `chat_template_kwargs: {"enable_thinking": false}` disables the `<think>` block on a single call without restarting the server. Qwen3.6 exposes this cleanly; by contrast Qwen3.5-122B on the cloud had an infinite-thinking bug on bartowski's Q4_K_M GGUF that only the latest Unsloth UD build fixed. Keep thinking ON as the server default (it's required for proper agentic coding) and disable per-request for pure extraction calls.

### Qwen3.5 — Official Recommended Parameters

Same values as Qwen3.6 above. Qwen team has not changed the defaults between 3.5 and 3.6.

### Gemma 4 — Tested Parameters

| Parameter | Value | Notes |
|---|---|---|
| temperature | 1.0 | Trained with temp=1.0, unlike Qwen3.5's 0.6 for coding |
| top_k | 64 | Higher than Qwen3.5's 20 — dense model benefits from broader sampling |
| top_p | 0.95 | Standard |
| min_p | 0.0 | Standard |
| presence_penalty | 0.0 | No penalty needed |

**Key difference**: Qwen3.5 needs `temp=0.6` for coding (temp=1.0 makes it sloppy), while Gemma 4 works well at `temp=1.0` because its training distribution accounts for this temperature. Using Qwen3.5's parameters on Gemma 4 (or vice versa) produces worse output.

## What Ollama Gets Wrong

Ollama's default Modelfile for `qwen3.5:35b-a3b` ships with:
```
PARAMETER temperature 1.0
PARAMETER presence_penalty 1.5
PARAMETER top_k 20
PARAMETER top_p 0.95
```

**Problems:**
1. `temperature=1.0` — Too random for coding. Should be 0.6.
2. `presence_penalty=1.5` — Actively hurts code quality by forcing the model to avoid repeating tokens. Code *needs* repeated patterns (variable names, function calls, syntax). Should be 0.0.

**Impact**: The model felt "sloppy" compared to qwen3-coder because of these defaults, not because the model was worse.

## Community Findings (r/LocalLLaMA)

### KV Cache Sensitivity
> "This model might be sensitive to KV cache quantization. I had both K and V type set to q8_0 for the 35b moe model, but as the context grew to about 20-40K tokens, it kept making minor mistakes with LaTeX."

**Our finding**: Confirmed for Qwen3.5. Standard q8_0 KV cache degrades quality. TurboQuant turbo3 does not. Gemma 4 has not been tested with KV cache quantization yet, but its dense architecture and SWA layers make it a different case.

### Tool Schema Tax
> "Tool schema size is a real tax on local models. Swapped frameworks — went from 11 tools to 5. Same model, same hardware. Response time went from ~5 min to ~1 min."

**Our finding**: Applies to both models equally. Claude Code sends 50+ MCP tool schemas. OpenCode sends ~10. Use OpenCode for local models regardless of which model you run.

### Chat Template Matters
> "Make sure to pass an explicit chat template from base model, not use the embedded one in GGUF."

**Our finding**: llama-server handles this automatically for both Qwen3.5 and Gemma 4. Ollama needs `RENDERER qwen3.5` and `PARSER qwen3.5` in the Modelfile for Qwen3.5 tool calling support.

### RTX 5090 Performance
> "Qwen3.5-35B-A3B-GGUF:UD-Q4_K_XL 180 t/s on 5090"

**Our findings**:
- Qwen3.5: 188 t/s confirmed (mainline f16 KV). 131 t/s with TurboQuant turbo3.
- Gemma 4: 61 t/s (mainline f16 KV). Dense architecture = 3.1x slower than MoE.

## Flash Attention
Must be enabled (`-fa on`) for both models. Without it:
- Slower inference
- Higher VRAM usage
- No fused Gated Delta Net kernels (Qwen3.5)

llama.cpp b8467+ changed the flag from `-fa` (bare) to `-fa on` (explicit value).

## Context Window Recommendations

### Qwen3.5
- **131,072 tokens**: Sweet spot for 32GB GPU. Leaves headroom for compute buffers.
- **262,144 tokens**: Possible with TurboQuant turbo3 (saves ~1.8GB KV cache).
- Beyond 262K: Requires YaRN RoPE scaling (modify `config.json` rope_parameters).

### Gemma 4
- **131,072 tokens**: Maximum on 32GB GPU (only ~2.8GB free). Tight but workable.
- **65,536 tokens**: Comfortable on 32GB GPU with room to spare.
- **32,768-65,536 tokens**: Recommended for 24GB GPUs.
- SWA layers use a fixed 4096-token window regardless of context size setting.
