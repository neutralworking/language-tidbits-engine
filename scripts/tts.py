#!/usr/bin/env python3
"""
tts.py — Generate voiceover audio using Kokoro (or compatible) TTS API.

Usage:
    python3 scripts/tts.py --text "The word OK was invented as a joke." --output assets/audio/001_voiceover.wav
    python3 scripts/tts.py --file script.txt --output assets/audio/001_voiceover.wav
    echo "Some text" | python3 scripts/tts.py --output assets/audio/001_voiceover.wav

Options:
    --text TEXT        Text to convert to speech
    --file FILE        Read text from file
    --output FILE      Output audio path (required)
    --voice VOICE      Voice ID (default: env TTS_VOICE or af_heart)
    --engine ENGINE    Engine name (default: env TTS_ENGINE or kokoro)
    --api-url URL      TTS API URL (default: env TTS_API_URL)
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error
from pathlib import Path


def load_env(repo_dir: Path) -> None:
    """Load .env file into os.environ if it exists."""
    env_file = repo_dir / ".env"
    if not env_file.exists():
        return
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())


def get_audio_duration(filepath: str, ffprobe_bin: str = "ffprobe") -> str:
    """Get audio duration using ffprobe."""
    try:
        result = subprocess.run(
            [ffprobe_bin, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", filepath],
            capture_output=True, text=True, check=True,
        )
        return f"{float(result.stdout.strip()):.2f}"
    except (subprocess.CalledProcessError, ValueError):
        return "unknown"


def main() -> None:
    repo_dir = Path(__file__).resolve().parent.parent
    load_env(repo_dir)

    parser = argparse.ArgumentParser(description="Generate TTS audio via Kokoro-compatible API")
    parser.add_argument("--text", help="Text to convert to speech")
    parser.add_argument("--file", help="Read text from file")
    parser.add_argument("--output", required=True, help="Output audio file path")
    parser.add_argument("--voice", default=os.environ.get("TTS_VOICE", "af_heart"))
    parser.add_argument("--engine", default=os.environ.get("TTS_ENGINE", "kokoro"))
    parser.add_argument("--api-url", default=os.environ.get("TTS_API_URL", "http://localhost:8880/v1/audio/speech"))
    args = parser.parse_args()

    # Resolve input text
    if args.text:
        text = args.text
    elif args.file:
        if not os.path.isfile(args.file):
            print(f"Error: File not found: {args.file}", file=sys.stderr)
            sys.exit(1)
        with open(args.file) as f:
            text = f.read()
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        print("Error: Provide text via --text, --file, or stdin.", file=sys.stderr)
        sys.exit(1)

    text = text.strip()
    if not text:
        print("Error: Input text is empty.", file=sys.stderr)
        sys.exit(1)

    # Ensure output directory exists
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)

    print(f"TTS engine:  {args.engine}")
    print(f"Voice:       {args.voice}")
    print(f"API URL:     {args.api_url}")
    print(f"Text length: {len(text)} chars")
    print()

    # Build request
    payload = json.dumps({
        "input": text,
        "voice": args.voice,
        "model": args.engine,
    }).encode("utf-8")

    req = urllib.request.Request(
        args.api_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    # Call TTS API
    try:
        with urllib.request.urlopen(req) as resp:
            audio_data = resp.read()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:500]
        print(f"Error: TTS API returned HTTP {e.code}", file=sys.stderr)
        if body:
            print(body, file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"Error: Cannot reach TTS API at {args.api_url}", file=sys.stderr)
        print(f"  {e.reason}", file=sys.stderr)
        print("  Is the TTS service running? Try: docker compose up -d", file=sys.stderr)
        sys.exit(1)

    if not audio_data:
        print("Error: TTS API returned empty response.", file=sys.stderr)
        sys.exit(1)

    # Write output
    with open(args.output, "wb") as f:
        f.write(audio_data)

    # Report
    ffprobe_bin = os.environ.get("FFPROBE_BIN", "ffprobe")
    duration = get_audio_duration(args.output, ffprobe_bin)
    size_bytes = os.path.getsize(args.output)
    size_human = f"{size_bytes / 1024:.0f}K" if size_bytes < 1048576 else f"{size_bytes / 1048576:.1f}M"

    print(f"Output:   {args.output}")
    print(f"Size:     {size_human}")
    print(f"Duration: {duration}s")
    print()
    print(f"Play it:  ffplay {args.output}")


if __name__ == "__main__":
    main()
