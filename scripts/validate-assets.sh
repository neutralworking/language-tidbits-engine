#!/usr/bin/env bash
#
# validate-assets.sh — Check that all required tools and assets are available
# before attempting a render.
#
# Usage:
#   ./scripts/validate-assets.sh [--audio FILE] [--subtitles FILE] [--background FILE]
#
# With no arguments, checks general system readiness.
# With file arguments, also checks that specific render inputs exist and are valid.

set -euo pipefail

ERRORS=0
WARNINGS=0

error() { echo "  ERROR: $1"; ((ERRORS++)); }
warn()  { echo "  WARN:  $1"; ((WARNINGS++)); }
ok()    { echo "  OK:    $1"; }

echo "=== language-tidbits-engine asset validation ==="
echo ""

# --- Check required tools ---
echo "Checking tools..."

FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-ffprobe}"

if command -v "$FFMPEG_BIN" &>/dev/null; then
  VERSION=$("$FFMPEG_BIN" -version | head -1)
  ok "ffmpeg found: $VERSION"
else
  error "ffmpeg not found. Install with: sudo apt install ffmpeg"
fi

if command -v "$FFPROBE_BIN" &>/dev/null; then
  ok "ffprobe found"
else
  error "ffprobe not found. Install with: sudo apt install ffmpeg"
fi

if command -v python3 &>/dev/null; then
  PY_VERSION=$(python3 --version)
  ok "python3 found: $PY_VERSION"
else
  error "python3 not found"
fi

echo ""

# --- Check directories ---
echo "Checking directories..."

for dir in assets/backgrounds assets/audio assets/captions assets/overlays data/input data/output data/logs; do
  if [[ -d "$dir" ]]; then
    ok "$dir/ exists"
  else
    error "$dir/ missing. Run: mkdir -p $dir"
  fi
done

echo ""

# --- Check fonts ---
echo "Checking fonts..."

FONT_PATH="${FONT_PATH:-/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf}"
if [[ -f "$FONT_PATH" ]]; then
  ok "Font found: $FONT_PATH"
else
  warn "Font not found: $FONT_PATH"
  warn "Install with: sudo apt install fonts-dejavu-core"
  warn "Or set FONT_PATH in .env to a valid font file"
fi

echo ""

# --- Check default background ---
echo "Checking default assets..."

if [[ -f "assets/backgrounds/default.png" ]]; then
  ok "Default background found"
else
  warn "No default background at assets/backgrounds/default.png"
  warn "Create one: convert -size 1080x1920 xc:'#1a1a2e' assets/backgrounds/default.png"
  warn "Or use: ffmpeg -f lavfi -i color=c=0x1a1a2e:s=1080x1920 -frames:v 1 assets/backgrounds/default.png"
fi

echo ""

# --- Check .env ---
echo "Checking configuration..."

if [[ -f ".env" ]]; then
  ok ".env file found"
else
  warn ".env not found. Copy from .env.example: cp .env.example .env"
fi

echo ""

# --- Check specific render inputs (if provided) ---
AUDIO=""
SUBTITLES=""
BACKGROUND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audio) AUDIO="$2"; shift 2 ;;
    --subtitles) SUBTITLES="$2"; shift 2 ;;
    --background) BACKGROUND="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -n "$AUDIO" || -n "$SUBTITLES" || -n "$BACKGROUND" ]]; then
  echo "Checking render inputs..."

  if [[ -n "$AUDIO" ]]; then
    if [[ -f "$AUDIO" ]]; then
      DURATION=$("$FFPROBE_BIN" -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$AUDIO" 2>/dev/null || echo "unknown")
      ok "Audio file: $AUDIO (${DURATION}s)"
    else
      error "Audio file not found: $AUDIO"
    fi
  fi

  if [[ -n "$SUBTITLES" ]]; then
    if [[ -f "$SUBTITLES" ]]; then
      LINES=$(wc -l < "$SUBTITLES")
      ok "Subtitles file: $SUBTITLES ($LINES lines)"
    else
      error "Subtitles file not found: $SUBTITLES"
    fi
  fi

  if [[ -n "$BACKGROUND" ]]; then
    if [[ -f "$BACKGROUND" ]]; then
      ok "Background file: $BACKGROUND"
    else
      error "Background file not found: $BACKGROUND"
    fi
  fi

  echo ""
fi

# --- Summary ---
echo "=== Summary ==="
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"

if [[ $ERRORS -gt 0 ]]; then
  echo "Fix errors before running the pipeline."
  exit 1
else
  echo "System is ready."
  exit 0
fi
