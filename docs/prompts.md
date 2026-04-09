# Prompt Documentation

Each prompt file in `/prompts/` is a self-contained template designed for a specific stage of the pipeline. The LLM receives the prompt with variables substituted by n8n before the API call.

## Variable syntax

Variables in prompts use `{{variable_name}}` notation. n8n's expression system replaces these before sending to the LLM.

---

## prompts/topic_expander.txt

**Purpose:** Take a raw topic idea and expand it into a structured brief for script generation.

**Input variables:**
- `{{topic}}` — Raw topic string (e.g., "The word 'OK' origin")

**Expected output (JSON):**
```json
{
  "expanded_topic": "The surprising origin of the word OK",
  "angle": "Historical etymology with a surprising twist",
  "target_audience": "General audience, language enthusiasts",
  "hook_idea": "The most spoken word on Earth was invented as a joke",
  "key_fact": "OK originated as a humorous abbreviation of 'oll korrect' in 1830s Boston newspapers",
  "source_hint": "Boston Morning Post, 1839"
}
```

---

## prompts/short_script.txt

**Purpose:** Generate a complete short-form video script from an expanded topic brief.

**Input variables:**
- `{{expanded_topic}}` — Full JSON from topic_expander output

**Expected output (JSON):**
```json
{
  "hook": "The most used word on Earth was invented as a joke.",
  "fact": "In the 1830s, Boston newspaper writers had a trend of abbreviating misspelled phrases. OK stood for 'oll korrect' — a playful misspelling of 'all correct.'",
  "example": "It started as slang, spread through telegraph operators who loved its brevity, and now it's understood in virtually every language.",
  "cta": "Follow for more language secrets hiding in plain sight.",
  "full_script": "The most used word on Earth was invented as a joke. In the 1830s...",
  "estimated_duration_seconds": 28,
  "word_count": 62
}
```

**Constraints:**
- Total script: 40-80 words
- Duration target: 20-40 seconds
- Structure: Hook → Fact → Example/Contrast → CTA
- Language: Simple, globally understandable, no jargon

---

## prompts/metadata.txt

**Purpose:** Generate platform-ready metadata for YouTube Shorts and TikTok.

**Input variables:**
- `{{script}}` — Full script JSON from short_script output

**Expected output (JSON):**
```json
{
  "youtube_title": "This word was invented as a JOKE 🤯 #shorts #language",
  "youtube_description": "The word OK has the wildest origin story...",
  "tiktok_caption": "The most used word on Earth started as a 1830s newspaper joke 🤯 #languagefacts #etymology #english",
  "tags": ["language facts", "etymology", "word origins", "OK origin", "english language"],
  "category": "Education"
}
```

**Constraints:**
- YouTube title: under 70 characters, include #shorts
- TikTok caption: under 150 characters with hashtags
- Tags: 5-10 relevant tags
- No clickbait that contradicts the actual content

---

## prompts/fact_safety_check.txt

**Purpose:** Verify that the language fact in the script is accurate enough for public content. Flag oversimplifications, common myths, and disputed claims.

**Input variables:**
- `{{fact}}` — The fact section from the script
- `{{example}}` — The example section from the script
- `{{source_hint}}` — Source hint from topic expander (if available)

**Expected output (JSON):**
```json
{
  "is_safe": true,
  "confidence": "high",
  "concerns": "None significant. The OK origin from 'oll korrect' is well-documented.",
  "suggestion": "",
  "risk_level": "low",
  "common_myth_check": "This is not a common myth — it's the accepted etymology."
}
```

**Confidence levels:**
- `high` — Well-documented, widely accepted
- `medium` — Generally accepted but has some scholarly debate
- `low` — Disputed, oversimplified, or potentially misleading

**Gate rule:** If `is_safe = false` or `confidence = low`, the pipeline stops and the topic is flagged for human review.

---

## prompts/visual_brief.txt

**Purpose:** Generate instructions for the visual style of the video. In v1 this is stored for reference; in v2 it will drive template-based image generation.

**Input variables:**
- `{{script}}` — Full script JSON
- `{{metadata}}` — Metadata JSON (title, tags)

**Expected output (JSON):**
```json
{
  "background_color": "#1a1a2e",
  "background_style": "dark gradient with subtle texture",
  "text_color": "#ffffff",
  "accent_color": "#e94560",
  "mood": "intriguing, educational",
  "title_card_text": "The word OK was invented as a joke",
  "font_suggestion": "Bold sans-serif (e.g., Montserrat Bold)",
  "overlay_elements": ["subtle question mark pattern"]
}
```

**Notes:**
- v1 ignores most of this and uses a default background
- The brief is saved to output metadata for future template rendering
- Keep suggestions simple and achievable with basic image tools
