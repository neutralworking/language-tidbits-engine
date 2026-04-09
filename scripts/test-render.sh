#!/usr/bin/env bash
#
# test-render.sh — End-to-end render test using sample assets.
#
# Generates a synthetic voiceover (silent audio) and renders a test video
# using the sample SRT and default background. Proves the FFmpeg pipeline
# works without needing a real TTS engine.
#
# Usage:
#   ./scripts/test-render.sh
#
# Output: data/output/test_001_origin_of_ok.mp4

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

BACKGROUND="assets/backgrounds/default.png"
SUBTITLES="assets/captions/001.srt"
OUTPUT="data/output/test_001_origin_of_ok.mp4"
AUDIO="assets/audio/test_silent_28s.wav"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"

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

# --- Generate synthetic audio (28s silent WAV with a tone at the start) ---
# This simulates a voiceover so FFmpeg has an audio track to work with.
echo "Generating synthetic test audio (28s)..."
"$FFMPEG_BIN" -y \
  -f lavfi -i "sine=frequency=440:duration=0.5" \
  -f lavfi -i "anullsrc=r=24000:cl=mono" \
  -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[out]" \
  -map "[out]" \
  -t 28 \
  "$AUDIO" 2>/dev/null

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
