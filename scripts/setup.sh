#!/bin/bash
# Local AI Coding Pipeline — One-Command Setup
# Sets up llama.cpp (mainline + TurboQuant), OpenCode, and model configs
# Tested on: WSL Kali Linux, WSL Ubuntu, native Ubuntu/Debian
#
# Usage: bash setup.sh
# Author: James Arslan | License: MIT

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Colors and helpers
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "$(echo -e "${CYAN}$prompt [Y/n]:${NC} ")" yn
        yn="${yn:-y}"
    else
        read -rp "$(echo -e "${CYAN}$prompt [y/N]:${NC} ")" yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy] ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Environment detection
# ─────────────────────────────────────────────────────────────────────────────

info "Detecting environment..."

IS_WSL=false
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    IS_WSL=true
    success "WSL detected (Windows Subsystem for Linux)"
else
    success "Native Linux detected"
fi

IS_KALI=false
IS_UBUNTU=false
IS_DEBIAN=false
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        kali)   IS_KALI=true;  success "Distribution: Kali Linux" ;;
        ubuntu) IS_UBUNTU=true; success "Distribution: Ubuntu" ;;
        debian) IS_DEBIAN=true; success "Distribution: Debian" ;;
        *)      warn "Distribution: $ID (untested, proceeding anyway)" ;;
    esac
fi

INSTALL_DIR="$HOME"
BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: System dependencies
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Step 1/7: System Dependencies ===${NC}"

install_if_missing() {
    local cmd="$1"
    local pkg="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then
        success "$cmd already installed ($(command -v "$cmd"))"
        return 0
    fi
    info "Installing $pkg..."
    sudo apt-get install -y "$pkg"
    success "$cmd installed"
}

sudo apt-get update -qq

install_if_missing cmake cmake
install_if_missing g++ g++
install_if_missing git git
install_if_missing curl curl
install_if_missing wget wget
install_if_missing make make

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: CUDA Toolkit
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Step 2/7: CUDA Toolkit ===${NC}"

if command -v nvcc &>/dev/null; then
    NVCC_VERSION=$(nvcc --version | grep -oP 'release \K[0-9.]+')
    success "CUDA toolkit already installed (nvcc $NVCC_VERSION)"
elif confirm "CUDA toolkit not found. Install it now?"; then
    if $IS_WSL; then
        info "Setting up CUDA repo for WSL..."
        # Kali/non-Ubuntu WSL distros lack the NVIDIA GPG key in their keyring.
        # Use [trusted=yes] to bypass the GPG check for the CUDA repo.
        if $IS_KALI || ! $IS_UBUNTU; then
            warn "Using [trusted=yes] for CUDA repo (Kali/non-Ubuntu GPG workaround)"
            echo "deb [trusted=yes] https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/ /" \
                | sudo tee /etc/apt/sources.list.d/cuda-wsl.list > /dev/null
        else
            # Ubuntu WSL can use the proper keyring
            wget -qO - https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/3bf863cc.pub \
                | sudo gpg --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg 2>/dev/null || true
            echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/ /" \
                | sudo tee /etc/apt/sources.list.d/cuda-wsl.list > /dev/null
        fi
    else
        # Native Linux — detect Ubuntu version for correct repo
        UBUNTU_VER=$(lsb_release -rs 2>/dev/null | tr -d '.')
        UBUNTU_VER="${UBUNTU_VER:-2404}"
        info "Setting up CUDA repo for native Linux (ubuntu${UBUNTU_VER})..."
        wget -qO - "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VER}/x86_64/3bf863cc.pub" \
            | sudo gpg --dearmor -o /usr/share/keyrings/cuda-archive-keyring.gpg 2>/dev/null || true
        echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VER}/x86_64/ /" \
            | sudo tee /etc/apt/sources.list.d/cuda.list > /dev/null
    fi

    sudo apt-get update -qq
    # Install CUDA toolkit (compiler + libraries, no driver — WSL uses Windows driver)
    sudo apt-get install -y cuda-toolkit
    success "CUDA toolkit installed"
else
    warn "Skipping CUDA toolkit — builds will fail without it"
fi

# Add CUDA to PATH for this session and future sessions
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
if ! grep -q '/usr/local/cuda/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo '' >> "$HOME/.bashrc"
    echo '# CUDA toolkit' >> "$HOME/.bashrc"
    echo 'export PATH="/usr/local/cuda/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"' >> "$HOME/.bashrc"
    info "Added CUDA to ~/.bashrc"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Detect GPU architecture
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Step 3/7: GPU Detection ===${NC}"

CUDA_ARCH=""
GPU_NAME="Unknown"

if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs)
    COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' | xargs)
    if [ -n "$COMPUTE_CAP" ]; then
        CUDA_ARCH="$COMPUTE_CAP"
        success "GPU: $GPU_NAME (sm_${CUDA_ARCH})"
    fi
fi

if [ -z "$CUDA_ARCH" ]; then
    warn "Could not auto-detect GPU architecture"
    echo "  Common values: 120 (RTX 5090), 89 (RTX 4090), 86 (RTX 3090)"
    read -rp "Enter your GPU compute capability (e.g., 120): " CUDA_ARCH
    if [ -z "$CUDA_ARCH" ]; then
        error "GPU architecture required. Exiting."
        exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Build llama.cpp (mainline + TurboQuant)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Step 4/7: Building llama.cpp ===${NC}"

build_llama() {
    local name="$1"
    local dir="$2"
    local repo="$3"
    local branch="$4"
    local extra_cmake="$5"

    if [ -f "$dir/build/bin/llama-server" ]; then
        if confirm "$name already built at $dir. Rebuild?"; then
            rm -rf "$dir"
        else
            success "$name: using existing build"
            return 0
        fi
    fi

    info "Cloning $name..."
    if [ -n "$branch" ]; then
        git clone --branch "$branch" --depth 1 "$repo" "$dir"
    else
        git clone --depth 1 "$repo" "$dir"
    fi

    info "Building $name (this takes a few minutes)..."
    cd "$dir"
    cmake -B build \
        -DGGML_CUDA=ON \
        -DGGML_NATIVE=ON \
        -DGGML_CUDA_FA=ON \
        -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
        $extra_cmake
    cmake --build build -j"$(nproc)"

    if [ -f build/bin/llama-server ]; then
        success "$name: BUILD SUCCESS"
    else
        error "$name: BUILD FAILED"
        return 1
    fi
}

# Mainline llama.cpp
build_llama \
    "Mainline llama.cpp" \
    "$INSTALL_DIR/llama-cpp-mainline" \
    "https://github.com/ggml-org/llama.cpp.git" \
    "" \
    ""

# TurboQuant fork
build_llama \
    "TurboQuant fork" \
    "$INSTALL_DIR/llama-cpp-turboquant" \
    "https://github.com/spiritbuun/llama-cpp-turboquant-cuda.git" \
    "feature/turboquant-kv-cache" \
    "-DGGML_CUDA_FA_ALL_QUANTS=ON"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Node.js + OpenCode
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Step 5/7: Node.js & OpenCode ===${NC}"

NODE_MINIMUM=22

if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -ge "$NODE_MINIMUM" ]; then
        success "Node.js $(node -v) installed (>= $NODE_MINIMUM required)"
    else
        warn "Node.js $(node -v) is too old (need >= $NODE_MINIMUM)"
        if confirm "Install Node.js $NODE_MINIMUM via n (node version manager)?"; then
            curl -fsSL https://raw.githubusercontent.com/tj/n/master/bin/n | sudo bash -s "$NODE_MINIMUM"
            hash -r
            success "Node.js $(node -v) installed"
        fi
    fi
else
    info "Node.js not found"
    if confirm "Install Node.js $NODE_MINIMUM via n (node version manager)?"; then
        curl -fsSL https://raw.githubusercontent.com/tj/n/master/bin/n | sudo bash -s "$NODE_MINIMUM"
        hash -r
        success "Node.js $(node -v) installed"
    else
        warn "Skipping Node.js — OpenCode requires Node.js >= $NODE_MINIMUM"
    fi
fi

# Install OpenCode
if command -v opencode &>/dev/null; then
    success "OpenCode already installed"
else
    if command -v npm &>/dev/null; then
        info "Installing OpenCode..."
        npm install -g opencode
        success "OpenCode installed"
    else
        warn "npm not found — skipping OpenCode install"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Model path and configuration
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Step 6/7: Configuration ===${NC}"

# Prompt for model path
echo ""
echo "Model paths (GGUF files):"
echo "  Download Qwen3.5:  https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF"
echo "  Download Gemma 4:  https://huggingface.co/unsloth/gemma-4-31b-it-GGUF"
echo ""
read -rp "$(echo -e "${CYAN}Path to Qwen3.5 GGUF (or press Enter to skip):${NC} ")" QWEN_MODEL_PATH
read -rp "$(echo -e "${CYAN}Path to Gemma 4 GGUF (or press Enter to skip):${NC} ")" GEMMA_MODEL_PATH

QWEN_MODEL_PATH="${QWEN_MODEL_PATH:-YOUR_MODEL_PATH/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf}"
GEMMA_MODEL_PATH="${GEMMA_MODEL_PATH:-YOUR_MODEL_PATH/gemma-4-31b-it-UD-Q4_K_XL.gguf}"

# Optional Context7 API key
echo ""
read -rp "$(echo -e "${CYAN}Context7 API key (optional, press Enter to skip):${NC} ")" CONTEXT7_KEY
CONTEXT7_KEY="${CONTEXT7_KEY:-YOUR_CONTEXT7_API_KEY}"

# ─────────────────────────────────────────────────────────────────────────────
# Generate helper scripts in ~/bin/
# ─────────────────────────────────────────────────────────────────────────────

info "Generating helper scripts in $BIN_DIR..."

# start-qwen.sh
cat > "$BIN_DIR/start-qwen.sh" << SCRIPT
#!/bin/bash
# Start Qwen3.5-35B-A3B (mainline, f16 KV cache)
# Usage: start-qwen.sh [port] [context_size]
PORT="\${1:-10500}"
CTX="\${2:-131072}"

export PATH="/usr/local/cuda/bin:\$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}"

echo "=== Qwen3.5-35B-A3B (Mainline, f16 KV) ==="
echo "Model: $QWEN_MODEL_PATH"
echo "API:   http://localhost:\$PORT/v1"
echo "Context: \$CTX tokens | VRAM: ~24GB at 131K"
echo "Press Ctrl+C to stop"
echo ""

exec "$INSTALL_DIR/llama-cpp-mainline/build/bin/llama-server" \\
    -m "$QWEN_MODEL_PATH" \\
    -ngl 99 -fa on -c "\$CTX" -np 1 \\
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \\
    --host 0.0.0.0 --port "\$PORT"
SCRIPT
chmod +x "$BIN_DIR/start-qwen.sh"

# start-gemma.sh
cat > "$BIN_DIR/start-gemma.sh" << SCRIPT
#!/bin/bash
# Start Gemma 4 31B Dense (mainline, f16 KV cache)
# Usage: start-gemma.sh [port] [context_size]
PORT="\${1:-10500}"
CTX="\${2:-131072}"

export PATH="/usr/local/cuda/bin:\$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}"

echo "=== Gemma 4 31B Dense (Mainline, f16 KV) ==="
echo "Model: $GEMMA_MODEL_PATH"
echo "API:   http://localhost:\$PORT/v1"
echo "Context: \$CTX tokens | VRAM: ~29.8GB at 131K"
echo ""
echo "NOTE: Gemma 4 uses 11.4GB KV cache at 131K context (dense model)."
echo "      SWA (Sliding Window Attention) layers break prompt caching."
echo "Press Ctrl+C to stop"
echo ""

exec "$INSTALL_DIR/llama-cpp-mainline/build/bin/llama-server" \\
    -m "$GEMMA_MODEL_PATH" \\
    -ngl 99 -fa on -c "\$CTX" -np 1 \\
    --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0 \\
    --host 0.0.0.0 --port "\$PORT"
SCRIPT
chmod +x "$BIN_DIR/start-gemma.sh"

# start-turbo.sh
cat > "$BIN_DIR/start-turbo.sh" << SCRIPT
#!/bin/bash
# Start Qwen3.5-35B-A3B (TurboQuant, turbo3 KV cache)
# Usage: start-turbo.sh [port] [context_size] [layer_adaptive]
PORT="\${1:-10500}"
CTX="\${2:-131072}"
LA="\${3:-1}"

export PATH="/usr/local/cuda/bin:\$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:\${LD_LIBRARY_PATH:-}"
export TURBO_LAYER_ADAPTIVE="\$LA"

echo "=== Qwen3.5-35B-A3B (TurboQuant, turbo3 KV) ==="
echo "Model: $QWEN_MODEL_PATH"
echo "API:   http://localhost:\$PORT/v1"
echo "Context: \$CTX tokens | KV: turbo3 (3.5x compression)"
echo "Layer Adaptive: \$LA (1=quality, 5=extended, unset=max compression)"
echo "VRAM: ~22GB at 131K (saves ~1.8GB vs f16)"
echo "Press Ctrl+C to stop"
echo ""

exec "$INSTALL_DIR/llama-cpp-turboquant/build/bin/llama-server" \\
    -m "$QWEN_MODEL_PATH" \\
    -ngl 99 -fa on -ctk turbo3 -ctv turbo3 -c "\$CTX" -np 1 \\
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \\
    --host 0.0.0.0 --port "\$PORT"
SCRIPT
chmod +x "$BIN_DIR/start-turbo.sh"

# stop-server.sh
cat > "$BIN_DIR/stop-server.sh" << SCRIPT
#!/bin/bash
# Stop all running llama-server instances
if pkill -f llama-server 2>/dev/null; then
    echo "llama-server stopped"
else
    echo "No llama-server running"
fi
SCRIPT
chmod +x "$BIN_DIR/stop-server.sh"

success "Helper scripts created in $BIN_DIR"

# Add ~/bin to PATH if needed
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo '' >> "$HOME/.bashrc"
    echo '# Local AI helper scripts' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    info "Added $BIN_DIR to PATH in ~/.bashrc"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Generate OpenCode config
# ─────────────────────────────────────────────────────────────────────────────

OPENCODE_DIR="$HOME/.config/opencode"
mkdir -p "$OPENCODE_DIR"

if [ -f "$OPENCODE_DIR/opencode.json" ]; then
    if ! confirm "OpenCode config exists at $OPENCODE_DIR/opencode.json. Overwrite?"; then
        info "Keeping existing OpenCode config"
    else
        WRITE_OPENCODE=true
    fi
else
    WRITE_OPENCODE=true
fi

if [ "${WRITE_OPENCODE:-false}" = true ]; then
    cat > "$OPENCODE_DIR/opencode.json" << OCEOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama.cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local llama.cpp",
      "options": {
        "baseURL": "http://localhost:10500/v1"
      },
      "models": {
        "qwen3.5-coding": {
          "name": "Qwen3.5-35B-A3B (Fast, MoE)",
          "limit": { "context": 131072, "output": 32000 }
        },
        "gemma-4-31B": {
          "name": "Gemma 4 31B Dense (Quality)",
          "limit": { "context": 131072, "output": 32000 }
        }
      }
    }
  },
  "model": "llama.cpp/qwen3.5-coding",
  "permission": { "*": "allow" },
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"
      }
    },
    "chrome-devtools": {
      "type": "local",
      "command": ["npx", "-y", "chrome-devtools-mcp@latest",
                  "--executablePath", "/usr/bin/chromium",
                  "--chromeArg", "--no-sandbox"],
      "enabled": true
    }
  }
}
OCEOF
    success "OpenCode config written to $OPENCODE_DIR/opencode.json"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=========================================${NC}"
echo -e "${BOLD}  Setup Complete!${NC}"
echo -e "${BOLD}=========================================${NC}"
echo ""
echo -e "  ${GREEN}GPU:${NC}        $GPU_NAME (sm_${CUDA_ARCH})"
echo -e "  ${GREEN}Mainline:${NC}   $INSTALL_DIR/llama-cpp-mainline/build/bin/llama-server"
echo -e "  ${GREEN}TurboQuant:${NC} $INSTALL_DIR/llama-cpp-turboquant/build/bin/llama-server"
echo -e "  ${GREEN}OpenCode:${NC}   $(command -v opencode 2>/dev/null || echo 'not installed')"
echo -e "  ${GREEN}Node.js:${NC}    $(node -v 2>/dev/null || echo 'not installed')"
echo ""
echo "  Helper scripts in $BIN_DIR:"
echo "    start-qwen.sh   — Qwen3.5 (188 t/s, fast agentic coding)"
echo "    start-gemma.sh  — Gemma 4 31B (61 t/s, best quality/reasoning)"
echo "    start-turbo.sh  — Qwen3.5 + TurboQuant (3.5x KV compression)"
echo "    stop-server.sh  — Stop llama-server"
echo ""
echo "  Quick start:"
echo "    source ~/.bashrc"
echo "    start-qwen.sh              # Start the server"
echo "    cd your-project && opencode  # Start coding"
echo ""
if [ "$CONTEXT7_KEY" != "YOUR_CONTEXT7_API_KEY" ]; then
    echo "  Context7 API key: set"
else
    echo "  Context7: using free tier (set CONTEXT7_API_KEY env var for higher limits)"
fi
echo ""
echo -e "  ${CYAN}Models to download:${NC}"
echo "    Qwen3.5: https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF"
echo "    Gemma 4: https://huggingface.co/unsloth/gemma-4-31b-it-GGUF"
echo ""
