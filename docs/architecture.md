# Architecture

## System overview

The language-tidbits-engine is a linear pipeline that turns topic ideas into publishable short-form videos. Every run processes one topic at a time.

```
┌─────────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐
│ Content      │────▶│  n8n    │────▶│  LLM     │────▶│  TTS    │
│ Queue        │     │  (orch) │     │  (script) │     │  Engine │
│ (Sheets/     │     │         │     │           │     │ (Kokoro/│
│  Baserow)    │     │         │     │           │     │ Chtrbx) │
└─────────────┘     └────┬────┘     └──────────┘     └────┬────┘
                         │                                  │
                         │         ┌──────────┐            │
                         │────────▶│  FFmpeg  │◀───────────┘
                         │         │  (render)│
                         │         └────┬─────┘
                         │              │
                         ▼              ▼
                    ┌─────────┐   ┌──────────┐
                    │ Tracking│   │ Output   │
                    │ Sheet   │   │ MP4 file │
                    └─────────┘   └──────────┘
```

## Components

### 1. Content queue (Google Sheets / Baserow)

- Stores topic ideas with status tracking
- Columns: id, topic, status, created_at, processed_at
- n8n reads next row where status = `pending`
- After processing, status is updated to `ready_for_review`

### 2. n8n (orchestration)

- Self-hosted via Docker
- Runs the v1 linear workflow
- Calls LLM API for script generation and fact checking
- Calls TTS API for voiceover
- Triggers render script via Execute Command node
- Writes output metadata back to tracking sheet/CSV

### 3. LLM (script generation + fact checking)

- Called via HTTP Request nodes in n8n
- Used for: topic expansion, script writing, fact safety check, metadata generation, visual brief
- Prompt templates stored in `/prompts/` and loaded by n8n
- Can be Claude API, OpenAI-compatible local model, or any HTTP LLM endpoint

### 4. TTS engine (voiceover)

- Kokoro TTS or Chatterbox TTS, running locally
- Exposes an HTTP API (OpenAI-compatible `/v1/audio/speech` endpoint)
- Receives script text, returns WAV/MP3 audio file
- Audio saved to `assets/audio/` before render

### 5. FFmpeg (video assembly)

- Called via `scripts/render-short.sh` or `scripts/render-short.py`
- Inputs: background image, voiceover audio, subtitle file (SRT)
- Output: 9:16 MP4 (1080x1920) with burned-in captions
- Optional title card prepended
- No motion graphics — static background with text overlay

### 6. Output tracking

- `data/output/generated_videos.csv` tracks all generated videos
- `data/logs/pipeline_log.csv` tracks pipeline execution status
- Content queue row updated with final status

## Data flow

```
ideas.csv / Sheets row
  → topic_expander prompt → expanded topic
  → short_script prompt → script JSON (hook, fact, example, cta)
  → fact_safety_check prompt → safety verdict
  → metadata prompt → title, description, tags
  → visual_brief prompt → background/overlay instructions
  → TTS API → voiceover.wav
  → FFmpeg render → output.mp4
  → tracking CSV/sheet updated
  → status = ready_for_review
```

## Network topology (single server)

All components run on one Linux machine:

| Service | Default port | Protocol |
|---------|-------------|----------|
| n8n | 5678 | HTTP |
| TTS (Kokoro/Chatterbox) | 8880 | HTTP |
| LLM API (if local) | 8080 | HTTP |
| Orshot (optional) | 3000 | HTTP |
| Baserow (optional) | 8000 | HTTP |

## Deployment

Services are defined in `docker-compose.yml` at the repo root:

| Service | Image | Purpose |
|---------|-------|---------|
| n8n | `n8nio/n8n:latest` | Workflow orchestration |
| kokoro-tts | `ghcr.io/remsky/kokoro-fastapi:latest` | Local TTS |

```bash
# Start everything
docker compose up -d

# Check status
docker compose ps
```

n8n data and Kokoro models are stored in named Docker volumes (`n8n_data`, `kokoro_models`).

## File system layout

```
/home/operator/language-tidbits-engine/    # This repo
```

All services run in Docker — no separate installs needed beyond what `scripts/setup.sh` provides.

## Security notes

- No secrets in the repo — all credentials via `.env` or n8n credential store
- n8n should not be exposed to the public internet without auth
- TTS and LLM endpoints are localhost-only by default
