#!/usr/bin/env bash
#
# test-render.sh — End-to-end render test using sample assets.
#
# Generates a voiceover and renders a test video using the sample SRT and
# default background. Uses real TTS if Kokoro is running, otherwise falls
# back to synthetic audio.
#
# Usage:
#   ./scripts/test-render.sh            # auto-detect TTS
#   ./scripts/test-render.sh --tts      # force real TTS (fail if unavailable)
#   ./scripts/test-render.sh --no-tts   # force synthetic audio
#
# Output: data/output/test_001_origin_of_ok.mp4

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

BACKGROUND="assets/backgrounds/default.png"
SUBTITLES="assets/captions/001.srt"
OUTPUT="data/output/test_001_origin_of_ok.mp4"
AUDIO="assets/audio/test_voiceover.wav"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"

# Load .env if present
if [[ -f "$REPO_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_DIR/.env"
  set +a
fi

TTS_API_URL="${TTS_API_URL:-http://localhost:8880/v1/audio/speech}"

# --- Parse arguments ---
TTS_MODE="auto"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tts) TTS_MODE="force"; shift ;;
    --no-tts) TTS_MODE="skip"; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Sample script text for TTS
TEST_SCRIPT="Did you know the word OK was invented as a joke? In 1839, a Boston newspaper abbreviated 'all correct' as O.K. as a playful misspelling. It caught on, and now it's one of the most recognized words on the planet. What other words do you think started as jokes? Let us know in the comments."

echo "=== Test render ==="
echo ""

# --- Check prerequisites ---
if ! command -v "$FFMPEG_BIN" &>/dev/null; then
  echo "Error: ffmpeg not found. Install with: sudo apt install ffmpeg"
  exit 1
fi

if [[ ! -f "$BACKGROUND" ]]; then
  echo "Error: Default background not found at $BACKGROUND"
  echo "Run: sudo ./scripts/setup.sh"
  exit 1
fi

if [[ ! -f "$SUBTITLES" ]]; then
  echo "Error: Sample subtitles not found at $SUBTITLES"
  exit 1
fi

# --- Generate audio ---
USE_TTS=false

if [[ "$TTS_MODE" == "force" ]]; then
  USE_TTS=true
elif [[ "$TTS_MODE" == "auto" ]]; then
  # Check if TTS API is reachable
  if curl -s --connect-timeout 2 --max-time 5 "$TTS_API_URL" >/dev/null 2>&1; then
    USE_TTS=true
    echo "TTS service detected at $TTS_API_URL"
  else
    echo "TTS service not available — using synthetic audio"
  fi
fi

if [[ "$USE_TTS" == true ]]; then
  echo "Generating voiceover via TTS..."
  ./scripts/tts.sh --text "$TEST_SCRIPT" --output "$AUDIO"
else
  # Synthetic audio fallback (28s silent WAV with a tone at the start)
  echo "Generating synthetic test audio (28s)..."
  "$FFMPEG_BIN" -y \
    -f lavfi -i "sine=frequency=440:duration=0.5" \
    -f lavfi -i "anullsrc=r=24000:cl=mono" \
    -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[out]" \
    -map "[out]" \
    -t 28 \
    "$AUDIO" 2>/dev/null
fi

echo "Test audio: $AUDIO"
echo ""

# --- Run render ---
echo "Running render-short.sh..."
echo ""

./scripts/render-short.sh \
  --background "$BACKGROUND" \
  --audio "$AUDIO" \
  --subtitles "$SUBTITLES" \
  --title "OK was invented as a joke" \
  --output "$OUTPUT"

echo ""
echo "=== Test complete ==="

if [[ -f "$OUTPUT" ]]; then
  SIZE=$(du -h "$OUTPUT" | cut -f1)
  echo "Output: $OUTPUT ($SIZE)"
  echo ""
  echo "Play it:  ffplay $OUTPUT"
  echo "Or copy to your machine and check visually."
else
  echo "Error: Output file was not created."
  exit 1
fi
