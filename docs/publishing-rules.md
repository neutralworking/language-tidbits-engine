# Publishing Rules — Manual Review Checklist

All videos must pass this checklist before uploading to YouTube Shorts or TikTok. In v1, publishing is entirely manual.

## Pre-publish checklist

### Content accuracy
- [ ] The main fact is accurate and not an oversimplified myth
- [ ] The example or contrast is fair and not misleading
- [ ] No claims that could be easily debunked in comments
- [ ] Source is plausible (even if not cited in video, you should know it)

### Script quality
- [ ] Hook grabs attention in the first 2 seconds
- [ ] Script flows naturally when read aloud
- [ ] No jargon or overly academic language
- [ ] CTA feels natural, not forced
- [ ] Total duration is between 20 and 40 seconds

### Audio quality
- [ ] Voiceover is clear and understandable
- [ ] No audio glitches, cuts, or unnatural pauses
- [ ] Pacing feels natural (not too fast, not too slow)
- [ ] Volume is consistent throughout

### Video quality
- [ ] Aspect ratio is 9:16 (1080x1920)
- [ ] Captions are readable on mobile
- [ ] Captions are correctly timed to audio
- [ ] No text is cut off at edges
- [ ] Background is not distracting
- [ ] Title card (if present) is clean and readable

### Metadata
- [ ] YouTube title is under 70 characters and includes #shorts
- [ ] YouTube description is accurate and engaging
- [ ] TikTok caption is under 150 characters with relevant hashtags
- [ ] Tags are relevant (not spammy)
- [ ] No metadata contradicts the video content

### Platform compliance
- [ ] No copyrighted music or images
- [ ] No content that violates YouTube or TikTok community guidelines
- [ ] No misleading thumbnails or titles
- [ ] Content is appropriate for all ages

## Publishing workflow

1. Review the video in `data/output/`
2. Run through the checklist above
3. If anything fails, note it in the content queue and fix or discard
4. Upload to YouTube Shorts with the generated metadata
5. Upload to TikTok with the generated caption
6. Update the content queue row: set status to `published`, add publish date and URLs
7. Log the publish event in `data/logs/pipeline_log.csv`

## Rejection reasons to track

When rejecting a video, note the reason in the content queue:
- `fact_inaccurate` — The core fact is wrong or misleading
- `audio_poor` — TTS output has quality issues
- `caption_misaligned` — Subtitles don't match audio timing
- `too_long` — Video exceeds 45 seconds
- `too_short` — Video is under 15 seconds
- `boring_hook` — Hook doesn't grab attention
- `metadata_bad` — Title/description needs rework
- `other` — Free text explanation

## Posting schedule (suggested)

- Start with 1 video per day to test engagement
- Scale to 2-3 per day once pipeline is reliable
- Post at consistent times (test different slots)
- Avoid posting identical content to both platforms simultaneously — stagger by 24 hours
