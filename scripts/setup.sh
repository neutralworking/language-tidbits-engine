#!/usr/bin/env bash
#
# setup.sh — Install dependencies for language-tidbits-engine on Ubuntu 22.04+
#
# Usage:
#   sudo ./scripts/setup.sh
#
# What it installs:
#   - FFmpeg (video assembly)
#   - Python 3 (render script)
#   - DejaVu fonts (subtitle rendering)
#   - Docker + Docker Compose (for n8n and TTS)
#
# What it does NOT install:
#   - n8n (use docker-compose.yml instead)
#   - TTS engine (use docker-compose.yml or install manually)
#   - LLM API (external service or separate local install)

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/setup.sh"
  exit 1
fi

echo "=== language-tidbits-engine setup ==="
echo ""

# --- System packages ---
echo "Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
  ffmpeg \
  python3 \
  python3-pip \
  fonts-dejavu-core \
  curl \
  git \
  jq

echo ""

# --- Docker (if not installed) ---
if command -v docker &>/dev/null; then
  echo "Docker already installed: $(docker --version)"
else
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  echo "Docker installed: $(docker --version)"
fi

# --- Docker Compose (if not installed) ---
if command -v docker compose &>/dev/null; then
  echo "Docker Compose already available: $(docker compose version)"
elif command -v docker-compose &>/dev/null; then
  echo "Docker Compose (standalone) already installed: $(docker-compose --version)"
else
  echo "Installing Docker Compose plugin..."
  apt-get install -y -qq docker-compose-plugin
  echo "Docker Compose installed: $(docker compose version)"
fi

echo ""

# --- Repo setup ---
echo "Setting up repo directories..."
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Ensure all directories exist
mkdir -p "$REPO_DIR"/{assets/{overlays,backgrounds,audio,captions},data/{input,output,logs}}

# Copy .env if it doesn't exist
if [[ ! -f "$REPO_DIR/.env" ]]; then
  cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
  echo "Created .env from .env.example — edit it with your values"
else
  echo ".env already exists"
fi

# Make scripts executable
chmod +x "$REPO_DIR"/scripts/*.sh
chmod +x "$REPO_DIR"/scripts/*.py

echo ""

# --- Generate default background if missing ---
if [[ ! -f "$REPO_DIR/assets/backgrounds/default.png" ]]; then
  echo "Generating default background image..."
  ffmpeg -y -f lavfi -i "color=c=0x1a1a2e:s=1080x1920:d=1" \
    -frames:v 1 "$REPO_DIR/assets/backgrounds/default.png" 2>/dev/null
  echo "Created assets/backgrounds/default.png"
else
  echo "Default background already exists"
fi

echo ""

# --- Validate ---
echo "Running asset validation..."
"$REPO_DIR/scripts/validate-assets.sh" || true

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env with your API keys and config"
echo "  2. Start services:  docker compose up -d"
echo "  3. Import workflow:  Open n8n UI → Import → n8n/workflows/v1-language-tidbits-workflow.json"
echo "  4. Test render:     ./scripts/test-render.sh"
