-- language-tidbits-engine: content pipeline schema
-- Run: psql -U $POSTGRES_USER -d $POSTGRES_DB -f db/schema.sql

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- TOPICS — input queue of raw topic ideas
-- ============================================================
CREATE TABLE topics (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            TEXT NOT NULL UNIQUE,
    raw_topic       TEXT NOT NULL,
    category        TEXT NOT NULL DEFAULT 'general',
    channel         TEXT NOT NULL DEFAULT 'language-tidbits',
    priority        TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high')),
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'ingesting', 'ingested', 'processing', 'processed', 'ready', 'published', 'rejected', 'error')),
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_topics_status ON topics(status);
CREATE INDEX idx_topics_channel ON topics(channel);

-- ============================================================
-- SOURCE_DOCUMENTS — normalized content from Wikipedia, Reddit, etc.
-- ============================================================
CREATE TABLE source_documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id        UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    source_type     TEXT NOT NULL CHECK (source_type IN ('wikipedia', 'reddit_post', 'reddit_comment', 'manual')),
    source_url      TEXT,
    source_id       TEXT,                   -- external ID (Wikipedia page ID, Reddit post ID, etc.)
    title           TEXT,
    content_text    TEXT NOT NULL,           -- plain text content
    content_html    TEXT,                    -- original HTML if available
    author          TEXT,
    score           INTEGER,                -- Reddit score, etc.
    metadata        JSONB NOT NULL DEFAULT '{}',  -- source-specific fields
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    content_hash    TEXT NOT NULL,           -- SHA-256 of content_text for deduplication
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_source_docs_topic ON source_documents(topic_id);
CREATE INDEX idx_source_docs_type ON source_documents(source_type);
CREATE INDEX idx_source_docs_hash ON source_documents(content_hash);
CREATE UNIQUE INDEX idx_source_docs_dedupe ON source_documents(topic_id, source_type, source_id);

-- ============================================================
-- SUMMARIES — LLM-generated summaries of source documents
-- ============================================================
CREATE TABLE summaries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id        UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    summary_type    TEXT NOT NULL CHECK (summary_type IN ('source_summary', 'angle_extraction', 'combined_brief')),
    input_doc_ids   UUID[] NOT NULL,         -- which source_documents were used
    content         JSONB NOT NULL,          -- structured summary output
    model_used      TEXT,
    prompt_version  TEXT,                    -- tracks which prompt template version was used
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_summaries_topic ON summaries(topic_id);
CREATE INDEX idx_summaries_type ON summaries(summary_type);

-- ============================================================
-- VIDEO_SCRIPTS — structured scripts ready for production
-- ============================================================
CREATE TABLE video_scripts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id        UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    summary_id      UUID REFERENCES summaries(id),
    hook            TEXT NOT NULL,
    fact            TEXT NOT NULL,
    example         TEXT NOT NULL,
    cta             TEXT NOT NULL,
    full_script     TEXT NOT NULL,
    word_count      INTEGER NOT NULL,
    estimated_duration_seconds INTEGER NOT NULL,
    angle           TEXT,
    tone            TEXT DEFAULT 'intriguing',
    model_used      TEXT,
    prompt_version  TEXT,
    review_status   TEXT NOT NULL DEFAULT 'pending'
                    CHECK (review_status IN ('pending', 'approved', 'rejected', 'needs_edit')),
    reviewer_notes  TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_scripts_topic ON video_scripts(topic_id);
CREATE INDEX idx_scripts_review ON video_scripts(review_status);

-- ============================================================
-- VIDEO_PROMPT_QUEUE — final prompt packages for video generation
-- ============================================================
CREATE TABLE video_prompt_queue (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id        UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    script_id       UUID NOT NULL REFERENCES video_scripts(id) ON DELETE CASCADE,
    channel         TEXT NOT NULL DEFAULT 'language-tidbits',

    -- Script content (denormalized for self-contained packages)
    hook            TEXT NOT NULL,
    fact            TEXT NOT NULL,
    example         TEXT NOT NULL,
    cta             TEXT NOT NULL,
    full_script     TEXT NOT NULL,

    -- Scene-by-scene visual prompts
    scenes          JSONB NOT NULL,
    /*
    scenes format:
    [
        {
            "scene_number": 1,
            "section": "hook",
            "duration_seconds": 3,
            "text_overlay": "The most used word on Earth...",
            "visual_description": "Dark navy background, large white text fades in",
            "background": {"type": "solid", "color": "#1a1a2e"},
            "caption_text": "The most used word on Earth was invented as a joke."
        },
        ...
    ]
    */

    -- Metadata
    title           TEXT NOT NULL,
    description     TEXT,
    tags            TEXT[],
    youtube_title   TEXT,
    tiktok_caption  TEXT,

    -- Production status
    status          TEXT NOT NULL DEFAULT 'queued'
                    CHECK (status IN ('queued', 'rendering', 'rendered', 'ready_for_review', 'approved', 'published', 'rejected', 'error')),
    error_message   TEXT,
    output_path     TEXT,
    render_metadata JSONB DEFAULT '{}',

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_prompt_queue_status ON video_prompt_queue(status);
CREATE INDEX idx_prompt_queue_channel ON video_prompt_queue(channel);

-- ============================================================
-- PIPELINE_RUNS — audit log for pipeline executions
-- ============================================================
CREATE TABLE pipeline_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id        UUID REFERENCES topics(id) ON DELETE SET NULL,
    workflow_name   TEXT NOT NULL,
    stage           TEXT NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('started', 'completed', 'failed', 'skipped')),
    input_summary   JSONB,
    output_summary  JSONB,
    error_message   TEXT,
    duration_ms     INTEGER,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_pipeline_runs_topic ON pipeline_runs(topic_id);
CREATE INDEX idx_pipeline_runs_status ON pipeline_runs(status);

-- ============================================================
-- Helper function: update updated_at on row change
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_topics_updated_at
    BEFORE UPDATE ON topics FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_scripts_updated_at
    BEFORE UPDATE ON video_scripts FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_prompt_queue_updated_at
    BEFORE UPDATE ON video_prompt_queue FOR EACH ROW EXECUTE FUNCTION update_updated_at();
