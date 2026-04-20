# Add to ~/.bashrc for Claude Code with local model
# Usage: claude-qwen (launches Claude Code connected to local llama-server)

# Claude Code with local Qwen3.5-35B-A3B via llama-server
claude-qwen() {
    ANTHROPIC_BASE_URL=http://localhost:10500 \
    ANTHROPIC_API_KEY=no-key \
    claude --model "qwen3.5-coding-unsloth" "$@"
}

# Note: Claude Code requires tool support in the model.
# If using Ollama, the model needs RENDERER and PARSER set:
#   TEMPLATE {{ .Prompt }}
#   RENDERER qwen3.5
#   PARSER qwen3.5
# llama-server handles this automatically via the chat template.
