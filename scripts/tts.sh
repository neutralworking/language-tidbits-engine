#!/usr/bin/env bash
#
# tts.sh — Generate voiceover audio using Kokoro (or compatible) TTS API.
#
# Usage:
#   ./scripts/tts.sh --text "The word OK was invented as a joke in 1839." --output assets/audio/001_voiceover.wav
#   ./scripts/tts.sh --file prompts/example_script.txt --output assets/audio/001_voiceover.wav
#   echo "Some text" | ./scripts/tts.sh --output assets/audio/001_voiceover.wav
#
# Options:
#   --text TEXT        Text to convert to speech
#   --file FILE        Read text from file instead
#   --output FILE      Output audio file path (required)
#   --voice VOICE      Voice ID (default: $TTS_VOICE or af_heart)
#   --engine ENGINE    TTS engine name (default: $TTS_ENGINE or kokoro)
#   --api-url URL      TTS API URL (default: $TTS_API_URL or http://localhost:8880/v1/audio/speech)
#
# Reads from stdin if neither --text nor --file is given.
#
# Requires: curl, ffprobe

set -euo pipefail

# --- Load .env if present ---
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$REPO_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_DIR/.env"
  set +a
fi

# --- Defaults from env ---
TTS_API_URL="${TTS_API_URL:-http://localhost:8880/v1/audio/speech}"
TTS_VOICE="${TTS_VOICE:-af_heart}"
TTS_ENGINE="${TTS_ENGINE:-kokoro}"
FFPROBE_BIN="${FFPROBE_BIN:-ffprobe}"

# --- Parse arguments ---
INPUT_TEXT=""
INPUT_FILE=""
OUTPUT=""
VOICE="$TTS_VOICE"
ENGINE="$TTS_ENGINE"
API_URL="$TTS_API_URL"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) INPUT_TEXT="$2"; shift 2 ;;
    --file) INPUT_FILE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --voice) VOICE="$2"; shift 2 ;;
    --engine) ENGINE="$2"; shift 2 ;;
    --api-url) API_URL="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# --- Validate ---
if [[ -z "$OUTPUT" ]]; then
  echo "Error: --output is required."
  exit 1
fi

# --- Resolve input text ---
if [[ -n "$INPUT_TEXT" ]]; then
  TEXT="$INPUT_TEXT"
elif [[ -n "$INPUT_FILE" ]]; then
  if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: File not found: $INPUT_FILE"
    exit 1
  fi
  TEXT=$(cat "$INPUT_FILE")
elif [[ ! -t 0 ]]; then
  TEXT=$(cat)
else
  echo "Error: Provide text via --text, --file, or stdin."
  exit 1
fi

if [[ -z "$TEXT" ]]; then
  echo "Error: Input text is empty."
  exit 1
fi

# --- Ensure output directory exists ---
mkdir -p "$(dirname "$OUTPUT")"

# --- Call TTS API ---
echo "TTS engine:  $ENGINE"
echo "Voice:       $VOICE"
echo "API URL:     $API_URL"
echo "Text length: ${#TEXT} chars"
echo ""

# Build JSON payload (escape text for JSON)
JSON_TEXT=$(printf '%s' "$TEXT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

HTTP_CODE=$(curl -s -w '%{http_code}' -o "$OUTPUT" \
  -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "{\"input\": ${JSON_TEXT}, \"voice\": \"${VOICE}\", \"model\": \"${ENGINE}\"}")

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Error: TTS API returned HTTP $HTTP_CODE"
  # Output file may contain error message
  if [[ -f "$OUTPUT" ]]; then
    head -c 500 "$OUTPUT"
    echo ""
    rm -f "$OUTPUT"
  fi
  exit 1
fi

# --- Validate output ---
if [[ ! -s "$OUTPUT" ]]; then
  echo "Error: TTS API returned empty response."
  rm -f "$OUTPUT"
  exit 1
fi

# --- Report ---
DURATION=$("$FFPROBE_BIN" -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT" 2>/dev/null || echo "unknown")
SIZE=$(du -h "$OUTPUT" | cut -f1)

echo "Output:   $OUTPUT"
echo "Size:     $SIZE"
echo "Duration: ${DURATION}s"
echo ""
echo "Play it:  ffplay $OUTPUT"
