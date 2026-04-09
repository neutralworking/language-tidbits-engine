# n8n Credentials Schema

These credentials must be configured in n8n before the workflow can run. Do not store actual secrets in this file or in the repo.

## Required credentials

### 1. Google Sheets OAuth2 (if using Google Sheets)

**n8n credential type:** `googleSheetsOAuth2Api`

| Field | Value |
|-------|-------|
| Client ID | From Google Cloud Console |
| Client Secret | From Google Cloud Console |
| Scope | `https://www.googleapis.com/auth/spreadsheets` |

**Setup steps:**
1. Go to Google Cloud Console → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID (Desktop or Web application)
3. Enable Google Sheets API
4. In n8n, add Google Sheets OAuth2 credential and complete the OAuth flow

### 2. LLM API Key

**n8n credential type:** `httpHeaderAuth`

| Field | Value |
|-------|-------|
| Name | `Authorization` |
| Value | `Bearer your-api-key-here` |

**Notes:**
- If using Claude API: get key from console.anthropic.com
- If using a local LLM with OpenAI-compatible API: may not need auth, but set a dummy value
- The header name/value format depends on the LLM provider

### 3. Baserow API Token (if using Baserow instead of Google Sheets)

**n8n credential type:** `httpHeaderAuth`

| Field | Value |
|-------|-------|
| Name | `Authorization` |
| Value | `Token your-baserow-token-here` |

**Setup steps:**
1. In Baserow, go to Settings → API Tokens
2. Create a token with read/write access to your table

## Optional credentials

### 4. Orshot API (if using template-based image generation)

**n8n credential type:** `httpHeaderAuth`

Not needed for v1. Orshot runs locally without auth by default.

## Credential checklist

- [ ] Google Sheets OAuth2 configured and tested
- [ ] LLM API key configured and tested with a simple prompt
- [ ] TTS endpoint reachable (no credential needed if localhost)
- [ ] All placeholder credential IDs in workflow JSON replaced with real ones
