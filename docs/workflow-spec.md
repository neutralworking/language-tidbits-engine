# Workflow Specification — v1

## Overview

The v1 workflow is a **linear, single-item pipeline**. It processes one topic per execution. No branching, no parallel paths. Publishing is manual.

## Stages

### Stage 1: Load next topic

**Node type:** Google Sheets node (or HTTP Request for Baserow)
**Input:** None (triggered manually or on schedule)
**Output:** Single row with `id`, `topic`, `status`
**Filter:** First row where `status = pending`
**On success:** Pass topic to Stage 2
**On failure:** Log "no pending topics" and stop

**Notes:**
- If using Google Sheets, the node needs OAuth2 credentials
- If using Baserow, use an HTTP Request node with API token
- TODO: Exact Google Sheets node filter config depends on n8n version; test after import

### Stage 2: Expand topic

**Node type:** HTTP Request (to LLM API)
**Input:** Topic string from Stage 1
**Prompt:** `prompts/topic_expander.txt` with topic inserted
**Output:** JSON with `expanded_topic`, `angle`, `target_audience`, `hook_idea`
**On failure:** Log error, mark topic as `error` in sheet, stop

### Stage 3: Generate script

**Node type:** HTTP Request (to LLM API)
**Input:** Expanded topic JSON from Stage 2
**Prompt:** `prompts/short_script.txt` with expanded topic inserted
**Output:** JSON with `hook`, `fact`, `example`, `cta`, `full_script`, `estimated_duration_seconds`
**On failure:** Log error, mark topic as `error`, stop

**Validation:**
- `estimated_duration_seconds` must be between 15 and 45
- If outside range, log warning but continue

### Stage 4: Fact safety check

**Node type:** HTTP Request (to LLM API)
**Input:** Script JSON from Stage 3
**Prompt:** `prompts/fact_safety_check.txt` with fact and example inserted
**Output:** JSON with `is_safe` (boolean), `confidence` (high/medium/low), `concerns` (string), `suggestion` (string)
**On failure:** Log error, mark as `error`, stop

**Gate:**
- If `is_safe = false` or `confidence = low`: mark topic as `needs_review`, stop
- If `is_safe = true` and `confidence` is medium or high: continue

### Stage 5: Generate metadata

**Node type:** HTTP Request (to LLM API)
**Input:** Script JSON from Stage 3
**Prompt:** `prompts/metadata.txt` with script inserted
**Output:** JSON with `title`, `description`, `tags` (array), `youtube_title`, `tiktok_caption`
**On failure:** Log error, mark as `error`, stop

### Stage 6: Generate visual brief

**Node type:** HTTP Request (to LLM API)
**Input:** Script JSON from Stage 3 + metadata from Stage 5
**Prompt:** `prompts/visual_brief.txt` with script and metadata inserted
**Output:** JSON with `background_color`, `background_style`, `text_overlay`, `font_suggestion`, `mood`
**On failure:** Log warning, use defaults, continue

**Notes:**
- v1 uses a static default background; visual brief is for future use
- The brief is saved to output metadata for when template generation is added

### Stage 7: Generate voiceover

**Node type:** HTTP Request (to TTS API)
**Input:** `full_script` text from Stage 3
**Endpoint:** `POST /v1/audio/speech`
**Body:** `{ "input": "<script>", "voice": "<voice_id>", "model": "kokoro" }`
**Output:** Audio file (WAV/MP3)
**Save to:** `assets/audio/{topic_id}_voiceover.wav`
**On failure:** Log error, mark as `error`, stop

**Notes:**
- TODO: Exact request/response format depends on TTS engine version
- Kokoro's OpenAI-compatible endpoint is assumed
- Chatterbox may need a different request body

### Stage 8: Prepare render assets

**Node type:** Function node (JavaScript in n8n)
**Input:** All outputs from previous stages
**Actions:**
- Generate SRT subtitle file from script sections with estimated timings
- Save SRT to `assets/captions/{topic_id}.srt`
- Resolve background image path (default or specified)
- Build command arguments for render script
**Output:** JSON with `background_path`, `audio_path`, `subtitles_path`, `output_path`, `title_text`

**Notes:**
- SRT timing is estimated from word count; operator may need to adjust
- TODO: Auto-timing from audio duration would be a v2 improvement

### Stage 9: Render video

**Node type:** Execute Command
**Command:** `./scripts/render-short.sh --background <bg> --audio <audio> --subtitles <srt> --title "<title>" --output <output>`
**Input:** Paths from Stage 8
**Output:** MP4 file at `data/output/{topic_id}.mp4`
**On failure:** Log error with FFmpeg stderr, mark as `error`, stop

### Stage 10: Save output metadata

**Node type:** Google Sheets node (or HTTP Request for Baserow) + CSV append
**Input:** All metadata from previous stages + output file path
**Actions:**
- Append row to `data/output/generated_videos.csv`
- Append row to `data/logs/pipeline_log.csv` with status `completed`
- Update content queue row: set status to `ready_for_review`, add output path and timestamp
**On failure:** Log error (video is still usable, metadata is secondary)

## Error handling summary

| Stage | On error |
|-------|----------|
| 1 — Load topic | Stop gracefully, log "no topics" |
| 2 — Expand | Mark `error`, stop |
| 3 — Script | Mark `error`, stop |
| 4 — Fact check | Mark `needs_review` if unsafe, `error` if API fails |
| 5 — Metadata | Mark `error`, stop |
| 6 — Visual brief | Use defaults, log warning, continue |
| 7 — TTS | Mark `error`, stop |
| 8 — Prepare assets | Mark `error`, stop |
| 9 — Render | Mark `error`, stop |
| 10 — Save metadata | Log error, continue (video exists) |

## Human review points

1. **Before Stage 1:** Operator adds/approves topic ideas in the content queue
2. **After Stage 4:** If fact check fails, topic goes to `needs_review` for manual editing
3. **After Stage 10:** All completed videos are `ready_for_review` — operator watches, decides to publish or discard
4. **Publishing:** Entirely manual in v1 — upload to YouTube/TikTok by hand

## Credentials needed

See `n8n/credentials-schema.md` for full list.
