#!/usr/bin/env bash
#
# render-short.sh — Assemble a vertical short-form video from background + audio + subtitles.
#
# Usage:
#   ./scripts/render-short.sh \
#     --background assets/backgrounds/default.png \
#     --audio assets/audio/001_voiceover.wav \
#     --subtitles assets/captions/001.srt \
#     --output data/output/001_video.mp4 \
#     [--title "Title card text"] \
#     [--title-duration 3]
#
# Requires: ffmpeg, ffprobe

set -euo pipefail

# --- Defaults ---
TITLE_TEXT=""
TITLE_DURATION=3
VIDEO_WIDTH="${VIDEO_WIDTH:-1080}"
VIDEO_HEIGHT="${VIDEO_HEIGHT:-1920}"
VIDEO_FPS="${VIDEO_FPS:-30}"
VIDEO_CRF="${VIDEO_CRF:-23}"
FONT_PATH="${FONT_PATH:-/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf}"
FONT_SIZE="${FONT_SIZE:-48}"
FONT_COLOR="${FONT_COLOR:-white}"
CAPTION_BOX_COLOR="${CAPTION_BOX_COLOR:-black@0.6}"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-ffprobe}"

# --- Parse arguments ---
BACKGROUND=""
AUDIO=""
SUBTITLES=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --background) BACKGROUND="$2"; shift 2 ;;
    --audio) AUDIO="$2"; shift 2 ;;
    --subtitles) SUBTITLES="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --title) TITLE_TEXT="$2"; shift 2 ;;
    --title-duration) TITLE_DURATION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# --- Validate required args ---
if [[ -z "$BACKGROUND" || -z "$AUDIO" || -z "$SUBTITLES" || -z "$OUTPUT" ]]; then
  echo "Error: --background, --audio, --subtitles, and --output are required."
  echo "Run with --help for usage."
  exit 1
fi

for f in "$BACKGROUND" "$AUDIO" "$SUBTITLES"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: File not found: $f"
    exit 1
  fi
done

# --- Ensure output directory exists ---
mkdir -p "$(dirname "$OUTPUT")"

# --- Get audio duration ---
AUDIO_DURATION=$("$FFPROBE_BIN" -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$AUDIO")
echo "Audio duration: ${AUDIO_DURATION}s"

# --- Build the main video (background + audio + subtitles) ---
# Escape special characters in subtitle path for FFmpeg filter
SUBTITLES_ESCAPED=$(echo "$SUBTITLES" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')

MAIN_CMD=(
  "$FFMPEG_BIN" -y
  -loop 1 -i "$BACKGROUND"
  -i "$AUDIO"
  -vf "scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:force_original_aspect_ratio=decrease,pad=${VIDEO_WIDTH}:${VIDEO_HEIGHT}:(ow-iw)/2:(oh-ih)/2,subtitles=${SUBTITLES_ESCAPED}:force_style='FontSize=14,FontName=DejaVu Sans Bold,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=3,Outline=1,Shadow=0,MarginL=40,MarginR=40,MarginV=80,Alignment=2,BackColour=&H80000000,WrapStyle=1'"
  -c:v libx264 -preset medium -crf "$VIDEO_CRF" -tune stillimage
  -c:a aac -b:a 128k
  -r "$VIDEO_FPS"
  -shortest
  -movflags +faststart
  -t "$AUDIO_DURATION"
)

if [[ -n "$TITLE_TEXT" ]]; then
  # --- Two-pass: title card first, then main video ---
  TMPDIR=$(mktemp -d)
  TITLE_CARD="${TMPDIR}/title_card.mp4"
  MAIN_VIDEO="${TMPDIR}/main_video.mp4"
  CONCAT_LIST="${TMPDIR}/concat.txt"

  echo "Generating title card: \"${TITLE_TEXT}\""

  # Title card: colored background with centered text
  "$FFMPEG_BIN" -y \
    -f lavfi -i "color=c=0x1a1a2e:s=${VIDEO_WIDTH}x${VIDEO_HEIGHT}:d=${TITLE_DURATION}:r=${VIDEO_FPS}" \
    -f lavfi -i "anullsrc=r=44100:cl=stereo" \
    -vf "drawtext=text='${TITLE_TEXT}':fontfile=${FONT_PATH}:fontsize=64:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:line_spacing=20" \
    -c:v libx264 -preset medium -crf "$VIDEO_CRF" \
    -c:a aac -b:a 128k \
    -t "$TITLE_DURATION" \
    "$TITLE_CARD"

  echo "Generating main video segment..."
  "${MAIN_CMD[@]}" "$MAIN_VIDEO"

  # Concatenate title card + main video
  echo "file '${TITLE_CARD}'" > "$CONCAT_LIST"
  echo "file '${MAIN_VIDEO}'" >> "$CONCAT_LIST"

  "$FFMPEG_BIN" -y -f concat -safe 0 -i "$CONCAT_LIST" \
    -c copy -movflags +faststart "$OUTPUT"

  rm -rf "$TMPDIR"
else
  echo "Generating video (no title card)..."
  "${MAIN_CMD[@]}" "$OUTPUT"
fi

echo "Done: $OUTPUT"
"$FFPROBE_BIN" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT" | \
  xargs -I {} echo "Final duration: {}s"
