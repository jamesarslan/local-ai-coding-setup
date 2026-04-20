#!/bin/bash
# Start llama-server with optimal parameters per model
#
# Usage:
#   ./start-server.sh qwen  [model_path] [port] [context_size]
#   ./start-server.sh gemma [model_path] [port] [context_size]
#   ./start-server.sh turbo [model_path] [port] [context_size]
#
# Defaults: port=10500, context=131072
# Author: James Arslan | License: MIT

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────────────────────────────────────

MODE="${1:-qwen}"
MODEL="${2:-}"
PORT="${3:-10500}"
CTX="${4:-131072}"

# CUDA paths
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

MAINLINE_BIN="${LLAMA_MAINLINE:-$HOME/llama-cpp-mainline/build/bin/llama-server}"
TURBO_BIN="${LLAMA_TURBOQUANT:-$HOME/llama-cpp-turboquant/build/bin/llama-server}"

# ─────────────────────────────────────────────────────────────────────────────
# Model-specific parameters
# ─────────────────────────────────────────────────────────────────────────────

case "$MODE" in
    qwen)
        MODEL="${MODEL:-YOUR_MODEL_PATH/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf}"
        LLAMA_BIN="$MAINLINE_BIN"
        TEMP="0.6"
        TOP_P="0.95"
        TOP_K="20"
        MIN_P="0.0"
        LABEL="Qwen3.5-35B-A3B (Mainline, f16 KV)"
        MODEL_SIZE="20.7"
        KV_CACHE_SIZE="2.5"
        VRAM_EST="24.0"
        ;;
    gemma)
        MODEL="${MODEL:-YOUR_MODEL_PATH/gemma-4-31b-it-UD-Q4_K_XL.gguf}"
        LLAMA_BIN="$MAINLINE_BIN"
        TEMP="1.0"
        TOP_P="0.95"
        TOP_K="64"
        MIN_P="0.0"
        LABEL="Gemma 4 31B Dense (Mainline, f16 KV)"
        MODEL_SIZE="18.4"
        KV_CACHE_SIZE="11.4"
        VRAM_EST="29.8"
        ;;
    turbo)
        MODEL="${MODEL:-YOUR_MODEL_PATH/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf}"
        LLAMA_BIN="$TURBO_BIN"
        TEMP="0.6"
        TOP_P="0.95"
        TOP_K="20"
        MIN_P="0.0"
        LABEL="Qwen3.5-35B-A3B (TurboQuant, turbo3 KV)"
        MODEL_SIZE="20.7"
        KV_CACHE_SIZE="0.7"
        VRAM_EST="22.2"
        export TURBO_LAYER_ADAPTIVE="${TURBO_LAYER_ADAPTIVE:-1}"
        EXTRA_ARGS="-ctk turbo3 -ctv turbo3"
        ;;
    *)
        echo "Usage: $0 [qwen|gemma|turbo] [model_path] [port] [context_size]"
        echo ""
        echo "Modes:"
        echo "  qwen   Qwen3.5-35B-A3B  — 188 t/s gen, MoE (3B active), fast coding"
        echo "  gemma  Gemma 4 31B       — 61 t/s gen, dense (31B active), best quality"
        echo "  turbo  Qwen3.5 + turbo3  — 131 t/s gen, 3.5x KV cache compression"
        echo ""
        echo "Examples:"
        echo "  $0 qwen /path/to/model.gguf 10500 131072"
        echo "  $0 gemma /mnt/models/gemma4.gguf"
        echo "  $0 turbo"
        exit 1
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# Validation
# ─────────────────────────────────────────────────────────────────────────────

if [ ! -f "$LLAMA_BIN" ]; then
    echo "ERROR: llama-server not found at $LLAMA_BIN"
    echo "Run scripts/setup.sh to build llama.cpp"
    exit 1
fi

if [[ "$MODEL" == *"YOUR_MODEL_PATH"* ]]; then
    echo "ERROR: No model path provided"
    echo "Usage: $0 $MODE /path/to/model.gguf [port] [context_size]"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "ERROR: Model file not found: $MODEL"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# VRAM estimate
# ─────────────────────────────────────────────────────────────────────────────

# Scale KV cache estimate for non-default context sizes
if [ "$CTX" != "131072" ]; then
    KV_SCALE=$(echo "scale=1; $CTX / 131072" | bc 2>/dev/null || echo "1")
    KV_CACHE_SIZE=$(echo "scale=1; $KV_CACHE_SIZE * $KV_SCALE" | bc 2>/dev/null || echo "$KV_CACHE_SIZE")
    VRAM_EST=$(echo "scale=1; $MODEL_SIZE + $KV_CACHE_SIZE + 0.8" | bc 2>/dev/null || echo "$VRAM_EST")
fi

GPU_VRAM=""
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs)
    GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
fi

echo ""
echo "=== $LABEL ==="
echo "Model:     $MODEL"
echo "API:       http://localhost:$PORT/v1"
echo "Context:   $CTX tokens"
echo "Params:    temp=$TEMP, top_p=$TOP_P, top_k=$TOP_K, min_p=$MIN_P"
echo ""
echo "--- VRAM Estimate ---"
echo "  Model:     ${MODEL_SIZE} GB"
echo "  KV Cache:  ${KV_CACHE_SIZE} GB (at ${CTX} context)"
echo "  Compute:   ~0.8 GB"
echo "  Total:     ~${VRAM_EST} GB"
if [ -n "$GPU_VRAM" ]; then
    GPU_VRAM_GB=$(echo "scale=1; $GPU_VRAM / 1024" | bc 2>/dev/null || echo "?")
    echo "  GPU:       $GPU_NAME ($GPU_VRAM_GB GB)"
fi
echo ""

if [ "$MODE" = "turbo" ]; then
    echo "TurboQuant: turbo3 KV cache (3.5x compression)"
    echo "Layer Adaptive: $TURBO_LAYER_ADAPTIVE"
    echo ""
fi

if [ "$MODE" = "gemma" ]; then
    echo "NOTE: Gemma 4 uses Sliding Window Attention (SWA) which breaks prompt"
    echo "      caching. Each new request reprocesses the full prompt."
    echo ""
fi

echo "Press Ctrl+C to stop"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Launch
# ─────────────────────────────────────────────────────────────────────────────

exec "$LLAMA_BIN" \
    -m "$MODEL" \
    -ngl 99 \
    -fa on \
    -c "$CTX" \
    -np 1 \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --top-k "$TOP_K" \
    --min-p "$MIN_P" \
    --host 0.0.0.0 \
    --port "$PORT" \
    ${EXTRA_ARGS:-}
