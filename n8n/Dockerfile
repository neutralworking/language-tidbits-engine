# Custom n8n image for language-tidbits-engine.
#
# Extends the stock n8n image with the system tools needed by the
# studio-webhook render pipeline (Run TTS / Write SRT File / Render Video):
#
#   - ffmpeg + ffprobe : scripts/render-short.sh and scripts/tts.sh need them
#   - python3          : scripts/tts.sh shells out to python3 for JSON escaping
#                        and Write SRT File decodes base64 via `python3 -c`
#   - curl             : scripts/tts.sh POSTs to the Kokoro TTS API
#   - fonts-dejavu     : render-short.sh burns subtitles using DejaVuSans-Bold
#
# Build is driven by docker-compose.yml (`build: ./n8n`).

# Pinned to 1.108.2 because n8nio/n8n:latest has been switched to a
# Docker Hardened Image (DHI) variant that strips `apk`, breaking the
# `apk add` step below. Versioned tags still ship the regular Alpine
# base. Bump deliberately after verifying a newer tag still has apk.
FROM n8nio/n8n:1.108.2

USER root

RUN apk add --no-cache \
      ffmpeg \
      python3 \
      curl \
      font-dejavu \
    && mkdir -p /usr/share/fonts/truetype/dejavu \
    && ln -sf /usr/share/fonts/dejavu/DejaVuSans-Bold.ttf \
          /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf

USER node
