# language-tidbits-engine

Automated content engine for generating faceless YouTube Shorts and TikTok videos about interesting language facts.

## What this is

A single-operator pipeline that takes a language tidbit idea, expands it into a short script, generates voiceover audio, assembles a vertical video with captions, and queues it for manual review before publishing. No face camera. No cinematic AI video. Just solid, repeatable template-based content.

## Stack

| Component | Tool | Why |
|-----------|------|-----|
| Orchestration | n8n (self-hosted) | Free, visual, API-friendly |
| TTS | Kokoro TTS or Chatterbox TTS | Local, open-source, no API costs |
| Image generation | Orshot (template-based) | Deterministic, no GPU needed for basic use |
| Video assembly | FFmpeg | Reliable, scriptable, free |
| Content queue | Google Sheets or Baserow | Simple, accessible, no DB setup |
| Prompts | Plain text files in repo | Version-controlled, editable |
| LLM | Claude API or local model | Script generation, fact checking |

## Quick start

### Prerequisites

- Linux server (Ubuntu 22.04+ recommended)
- Docker and Docker Compose (for n8n)
- Python 3.10+
- FFmpeg 5.0+
- A TTS engine running locally (Kokoro or Chatterbox)

### Setup

```bash
# Clone the repo
git clone https://github.com/neutralworking/language-tidbits-engine.git
cd language-tidbits-engine

# Run the setup script (installs FFmpeg, Docker, fonts, creates .env)
sudo ./scripts/setup.sh

# Edit .env with your actual values
nano .env

# Start n8n + Kokoro TTS
docker compose up -d

# Import the n8n workflow
# Open n8n UI at http://localhost:5678
# Workflows → Import from File → select n8n/workflows/v1-language-tidbits-workflow.json
```

### Running a test render

```bash
# Quick test — uses real TTS if Kokoro is running, falls back to synthetic audio
./scripts/test-render.sh

# Generate voiceover directly
./scripts/tts.sh --text "The word OK was invented as a joke." --output assets/audio/001_voiceover.wav

# Manual render with real assets
./scripts/render-short.sh \
  --background assets/backgrounds/default.png \
  --audio assets/audio/001_voiceover.wav \
  --subtitles assets/captions/001.srt \
  --output data/output/001_video.mp4 \
  --title "OK was invented as a joke"
```

## v1 workflow

1. Add topic idea to content queue (Google Sheets / Baserow)
2. n8n picks up next unprocessed topic
3. LLM expands topic and generates script (hook → fact → example → CTA)
4. Fact safety check runs on the script
5. Metadata and visual brief are generated
6. TTS generates voiceover audio
7. FFmpeg assembles final 9:16 MP4 with burned captions
8. Output metadata saved to tracking sheet
9. Item marked `ready_for_review`
10. **Human reviews and publishes manually**

## Project structure

```
├── README.md              # This file
├── CLAUDE.md              # Rules for Claude Code sessions
├── .env.example           # Environment variable template
├── docker-compose.yml     # n8n + Kokoro TTS services
├── docs/                  # Architecture and workflow documentation
├── prompts/               # LLM prompt templates
├── data/
│   ├── input/             # Topic ideas and approved facts
│   ├── output/            # Generated video tracking
│   └── logs/              # Pipeline execution logs
├── n8n/
│   ├── workflows/         # Importable n8n workflow JSON
│   └── samples/           # Sample input/output for testing
├── scripts/
│   ├── setup.sh           # One-command Ubuntu dependency install
│   ├── test-render.sh     # End-to-end render test (auto-detects TTS)
│   ├── tts.sh             # TTS voiceover generation (bash)
│   ├── tts.py             # TTS voiceover generation (python)
│   ├── render-short.sh    # FFmpeg render (bash)
│   ├── render-short.py    # FFmpeg render (python)
│   └── validate-assets.sh # Pre-render checks
└── assets/                # Overlays, backgrounds, audio, captions
```

## Future improvements

- Automated publishing via YouTube/TikTok APIs
- A/B testing different hook styles
- Batch processing (multiple videos per run)
- Analytics feedback loop (performance → topic selection)
- Claude Code ↔ n8n MCP integration for workflow generation
- Thumbnail generation pipeline
- Multi-language support
