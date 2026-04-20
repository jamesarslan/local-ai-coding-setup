#!/bin/bash
# Run Open WebUI connected to local llama-server
# Access at http://localhost:5762
#
# NOTE on networking:
#   - From Docker on Windows/WSL: use host.docker.internal:10500
#     (Docker cannot reach WSL's localhost directly)
#   - From Docker on native Linux: use 172.17.0.1:10500 or --network host
#     (host.docker.internal may not resolve without --add-host)
#   - llama-server must bind to 0.0.0.0 (not 127.0.0.1) for Docker to reach it
#
# Author: James Arslan | License: MIT

set -e

PORT="${1:-10500}"

# Detect if running in WSL or native Linux for correct Docker networking
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    # WSL: Docker Desktop routes host.docker.internal to the Windows host,
    # which in turn can reach WSL's forwarded ports
    API_HOST="host.docker.internal"
else
    # Native Linux: use Docker's bridge gateway IP
    API_HOST="172.17.0.1"
fi

echo "Starting Open WebUI..."
echo "  Web UI:     http://localhost:5762"
echo "  API target: http://${API_HOST}:${PORT}/v1"
echo ""

docker run -d \
    -p 5762:8080 \
    --name open-webui \
    --volume open-webui:/app/backend/data \
    --restart always \
    -e OPENAI_API_BASE_URLS="http://${API_HOST}:${PORT}/v1" \
    -e OPENAI_API_KEYS="no-key" \
    -e OLLAMA_BASE_URL="" \
    -e WEBUI_AUTH=true \
    -e ENABLE_SIGNUP=true \
    -e CORS_ALLOW_ORIGIN="*" \
    -e SCARF_NO_ANALYTICS=true \
    -e DO_NOT_TRACK=true \
    -e ANONYMIZED_TELEMETRY=false \
    ghcr.io/open-webui/open-webui:main

echo ""
echo "Open WebUI running at http://localhost:5762"
echo "Connected to llama-server at ${API_HOST}:${PORT}"
echo ""
echo "To switch models: stop llama-server, start with different model, refresh Open WebUI"
echo "To stop: docker stop open-webui && docker rm open-webui"
