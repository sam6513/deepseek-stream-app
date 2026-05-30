#!/bin/bash
set -e

cd "$(dirname "$0")"

# Load API key from environment or .env file
if [ -z "$DEEPSEEK_API_KEY" ] && [ -f .env ]; then
  export DEEPSEEK_API_KEY=$(grep -v '^#' .env | grep '^DEEPSEEK_API_KEY=' | cut -d '=' -f2-)
fi

if [ -z "$DEEPSEEK_API_KEY" ]; then
  echo "Error: DEEPSEEK_API_KEY not set."
  echo "  export DEEPSEEK_API_KEY=sk-your-key  or  create .env file"
  exit 1
fi

echo "=== Building Docker image ==="
docker build \
  --build-arg DEEPSEEK_API_KEY="$DEEPSEEK_API_KEY" \
  -t deepseek-stream-app .

echo "=== Stopping old containers (if exist) ==="
docker stop open-webui 2>/dev/null || true
docker rm open-webui 2>/dev/null || true
docker stop deepseek-stream 2>/dev/null || true
docker rm deepseek-stream 2>/dev/null || true

echo "=== Starting new container ==="
docker run -d \
  --name deepseek-stream \
  --restart always \
  -p 127.0.0.1:8102:3000 \
  deepseek-stream-app

echo ""
echo "=== Done ==="
echo "Internal: curl http://127.0.0.1:8102"
echo "External: https://stream.zjjcfz.cn"
echo ""
echo "Check logs: docker logs -f deepseek-stream"
