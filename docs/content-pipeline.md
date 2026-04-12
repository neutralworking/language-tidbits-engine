# Content Pipeline — v2

## Overview

The content pipeline automates research and script generation. It is channel-agnostic — the same pipeline works for language-tidbits or any future channel by changing the `channel` column on topics.

```
Topics (Postgres)
  → v2-source-ingestion (n8n)
    → Wikipedia API (summary + full page)
    → Reddit JSON API (search posts)
    → Normalize → Deduplicate → Store in source_documents
  → v2-content-processing (n8n)
    → Load sources → Summarize (LLM) → Generate script + scenes (LLM)
    → Store in video_scripts + video_prompt_queue
  → Human review (manual)
  → v1-language-tidbits-workflow (existing render pipeline)
```

## Data flow

```
topics (pending)
  ↓ v2-source-ingestion
source_documents (wikipedia, reddit_post)
  ↓ v2-content-processing
summaries (source_summary)
  ↓
video_scripts (hook, fact, example, cta)
  ↓
video_prompt_queue (scenes, metadata, ready for render)
  ↓ human review
v1 render pipeline (FFmpeg → MP4)
```

## Postgres tables

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `topics` | Input queue | slug, raw_topic, category, channel, status, priority |
| `source_documents` | Normalized source content | topic_id, source_type, content_text, content_hash |
| `summaries` | LLM-generated research briefs | topic_id, summary_type, content (JSONB) |
| `video_scripts` | Structured scripts | topic_id, hook, fact, example, cta, review_status |
| `video_prompt_queue` | Final prompt packages | topic_id, script_id, scenes (JSONB), status |
| `pipeline_runs` | Audit log | topic_id, workflow_name, stage, status |

See `db/schema.sql` for full DDL.

## Source APIs

### Wikipedia (MediaWiki)

Two endpoints used:

**REST Summary API** (lightweight, returns extract + thumbnail):
```
GET https://en.wikipedia.org/api/rest_v1/page/summary/{title}
```
- No auth required
- Rate limit: be polite, ~1 req/sec
- Returns: extract, description, thumbnail, page URL
- If 404: topic title may not match Wikipedia — log and continue

**Action API** (full HTML, sections, categories):
```
GET https://en.wikipedia.org/w/api.php?action=parse&page={title}&prop=text|sections|categories&format=json
```
- No auth required
- Rate limit: 200 req/sec unauthed (but keep it under 1/sec per topic)
- Returns: parsed HTML, section headings, categories
- HTML is stripped to plain text during normalization

### Reddit (public JSON)

**Search endpoint:**
```
GET https://www.reddit.com/search.json?q={topic}&sort=relevance&limit=10&t=all
```
- No auth required for `.json` endpoints
- **Requires User-Agent header** (Reddit blocks generic/empty UAs)
- Rate limit: ~10 requests/minute
- Returns: posts with title, selftext, score, subreddit, comments count
- Top 5 posts by relevance are stored

**For higher rate limits** (v2 improvement):
- Register a Reddit app at reddit.com/prefs/apps
- Use OAuth2 with `https://oauth.reddit.com/search` endpoint
- Gets 60 req/min instead of 10

## Normalized source document schema

Every source (Wikipedia, Reddit, future sources) is stored in the same shape:

```json
{
  "topic_id": "uuid",
  "source_type": "wikipedia | reddit_post | reddit_comment | manual",
  "source_url": "https://...",
  "source_id": "external-id",
  "title": "Document title",
  "content_text": "Plain text content (max ~50KB)",
  "content_html": "Original HTML if available",
  "author": "author name or null",
  "score": 12345,
  "metadata": {
    "doc_subtype": "summary | full_page | post | comment",
    "subreddit": "todayilearned",
    "num_comments": 500,
    "categories": ["Linguistics"],
    "...": "source-specific fields"
  },
  "content_hash": "sha256-hex"
}
```

Adding a new source (e.g., Wiktionary, YouTube transcripts) means:
1. Add a new `source_type` value to the CHECK constraint
2. Add a fetch node in v2-source-ingestion
3. Add a normalize function that outputs this schema
4. Everything downstream (summarization, scripting) works unchanged

## Deduplication

Three layers:

1. **Content hash** — `content_hash` (SHA-256 of content_text) prevents storing identical content twice
2. **Unique index** — `(topic_id, source_type, source_id)` prevents duplicate fetches for the same source
3. **Upsert** — `ON CONFLICT DO UPDATE` refreshes content if re-fetched

## Rate limiting

| Source | Limit | Strategy |
|--------|-------|----------|
| Wikipedia REST | ~1 req/sec (polite) | Add 1s Wait node between topics |
| Wikipedia Action | 200 req/sec | Same Wait node covers this |
| Reddit JSON | ~10 req/min | Add 6s Wait node between Reddit fetches |
| LLM API | Depends on provider | Use n8n's built-in retry with backoff |

In the n8n workflow, add a **Wait** node (1-2 seconds) between batch items when processing multiple topics. For Reddit, increase to 6 seconds between calls.

## Retry strategy

| Stage | On failure | Retries |
|-------|------------|---------|
| Wikipedia fetch | Log warning, continue without Wikipedia | 2 retries, 5s backoff |
| Reddit fetch | Log warning, continue without Reddit | 2 retries, 10s backoff |
| LLM summarize | Mark topic as error, stop | 3 retries, exponential backoff |
| LLM scripting | Mark topic as error, stop | 3 retries, exponential backoff |
| Postgres write | Mark topic as error, stop | 1 retry |

Configure retries in n8n: Node Settings → On Error → Retry on Fail.

Source fetches are soft failures (pipeline continues with available data). LLM calls are hard failures (pipeline stops for that topic).

## Human review points

1. **After ingestion** — Operator can inspect source_documents to check coverage before processing
2. **After script generation** — `video_scripts.review_status` defaults to `pending`. Operator reviews and sets to `approved` or `rejected`
3. **After prompt queue** — `video_prompt_queue.status` can be held at `queued` until operator approves
4. **After render** — Same manual review as v1 (see docs/publishing-rules.md)

### Review queries

```sql
-- Scripts awaiting review
SELECT t.raw_topic, vs.hook, vs.fact, vs.word_count, vs.review_status
FROM video_scripts vs
JOIN topics t ON t.id = vs.topic_id
WHERE vs.review_status = 'pending'
ORDER BY vs.created_at;

-- Prompt queue ready to render
SELECT vpq.title, vpq.status, vpq.full_script
FROM video_prompt_queue vpq
WHERE vpq.status = 'queued'
ORDER BY vpq.created_at;

-- Pipeline health check
SELECT stage, status, COUNT(*), AVG(duration_ms) as avg_ms
FROM pipeline_runs
WHERE started_at > now() - interval '24 hours'
GROUP BY stage, status;
```

## Studio webhook (live end-to-end pipeline)

`n8n/workflows/studio-webhook.json` is the live pipeline behind the Studio page. Unlike `v2-source-ingestion` + `v2-content-processing` (which run on a schedule/trigger), the studio-webhook exposes HTTP endpoints that the Studio page calls directly:

| Path | Method | Purpose |
|------|--------|---------|
| `studio/submit`  | POST | Create topic + kick off full pipeline |
| `studio/status`  | GET  | Fetch a topic's status + script + `video_url` |
| `studio/topics`  | GET  | List recent topics |
| `studio/approve` | POST | Mark a queue entry approved + (stub) publish |
| `studio/reject`  | POST | Mark a topic rejected |

`studio/submit` runs the full pipeline in one execution:

```
Create Topic (pending)
  → Mark Ingesting → Wikipedia summary + HTML + Reddit (parallel, soft failures)
  → Normalize & Store Sources → Mark Ingested
  → Mark Processing → Prepare LLM Context
  → LLM: Summarize Sources → Parse → Store Summary
  → LLM: Generate Script + Scenes → Parse → Store Script
  → Queue Video Prompt (status='queued')
  → Prepare Render Assets (builds SRT, paths, shell commands)
  → Mark Rendering (queue.status='rendering')
  → Run TTS       (scripts/tts.sh → assets/audio/<slug>.wav)
  → Write SRT     (python3 → assets/captions/<slug>.srt)
  → Render Video  (scripts/render-short.sh → data/output/<slug>.mp4)
  → Update Queue Output (queue.status='rendered', output_path=...)
  → Mark Ready + Log Run (topic.status='ready')
```

Any failure along the LLM, parse, TTS, SRT, or render stages routes to the **Mark Error** node via `onError: continueErrorOutput`, which marks both `topics.status` and `video_prompt_queue.status` as `error`. Topics never stay stuck at `processing`.

Wikipedia/Reddit fetchers use `onError: continueRegularOutput` instead — a missing Wikipedia page is a soft failure; the Normalize code node skips the missing source via null guards.

The render steps (`Run TTS`, `Write SRT File`, `Render Video`) shell out via `executeCommand` inside the n8n container, which requires `ffmpeg`, `ffprobe`, `python3`, `curl`, and DejaVu fonts to be present. `n8n/Dockerfile` extends the stock `n8nio/n8n` image with those packages; `docker-compose.yml` builds from it.

The `studio/status` endpoint returns `video_url` by aliasing `video_prompt_queue.output_path AS video_url` so the Studio page's `<video>` element gets a path the moment `Update Queue Output` runs.

## Making it reusable for other channels

The pipeline is channel-agnostic by design:

1. Add topics with a different `channel` value (e.g., `brain-levelup`)
2. Source ingestion works the same — Wikipedia and Reddit don't care about your channel
3. Prompt templates use `{{category}}` and `{{channel}}` variables — customize per channel if needed
4. `video_prompt_queue.channel` lets you filter and route to different render pipelines

To add a new channel:
1. Insert topics with `channel = 'your-channel'`
2. Optionally create channel-specific prompt templates in `prompts/pipeline/`
3. Filter the content processing workflow by channel if needed
4. Create a channel-specific render template (or reuse the default)

## Database setup

```bash
# Create database
createdb language_tidbits

# Run schema
psql -U $POSTGRES_USER -d language_tidbits -f db/schema.sql

# Seed sample topics
psql -U $POSTGRES_USER -d language_tidbits -f db/seed-topics.sql
```

## Workflow import

Import both workflows into n8n:
1. `n8n/workflows/v2-source-ingestion.json` — run first
2. `n8n/workflows/v2-content-processing.json` — run after ingestion completes

Replace all `PLACEHOLDER` credential IDs with real n8n credential IDs after import.
