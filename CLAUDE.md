# CLAUDE.md — Rules for Claude Code Sessions

## Repo identity

This repo is **language-tidbits-engine**. It generates faceless short-form videos about language facts for YouTube Shorts and TikTok. Do not merge unrelated content niches (brain-levelup, etc.) into this repo.

## Core principles

- Simple working automation over cleverness
- Boring and reliable over novel and fragile
- One operator should be able to understand and run everything
- Prefer explicit over implicit in all configs and scripts

## File organization rules

- Prompts live in `/prompts/` as plain `.txt` files
- n8n workflow JSON lives in `/n8n/workflows/`
- Render scripts live in `/scripts/`
- Sample data and CSVs live in `/data/`
- Documentation lives in `/docs/`
- Assets (backgrounds, overlays, audio, captions) live in `/assets/`

## When modifying workflows

- Update `docs/workflow-spec.md` whenever the n8n workflow changes
- Update `docs/prompts.md` if any prompt file changes
- Keep `n8n/samples/sample-input.json` and `sample-output.json` consistent with the workflow

## Code style

- Shell scripts: bash, explicit error handling, quoted variables
- Python scripts: stdlib preferred, minimal dependencies, no frameworks
- No magic abstractions or unnecessary indirection
- Comments where logic isn't obvious, not everywhere

## What not to do

- Do not add AI video generation tools (Runway, Pika, etc.) — this is template-based
- Do not add automated publishing in v1 — publishing is manual
- Do not create new content niches in this repo
- Do not add dependencies without justification
- Do not invent n8n node parameters — use documented configs or leave TODOs
- Do not add environment variables without updating `.env.example`

## Testing

- Run `./scripts/validate-assets.sh` before render attempts
- Test render scripts with sample assets before pipeline runs
- Check CSV schemas match expected formats after workflow changes

## Commit conventions

- Prefix commits with area: `docs:`, `prompts:`, `scripts:`, `n8n:`, `data:`
- Keep commits focused on one change area
