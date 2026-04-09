#!/usr/bin/env python3
"""
render-short.py — Assemble a vertical short-form video from background + audio + subtitles.

Usage:
    python3 scripts/render-short.py \
        --background assets/backgrounds/default.png \
        --audio assets/audio/001_voiceover.wav \
        --subtitles assets/captions/001.srt \
        --output data/output/001_video.mp4 \
        [--title "Title card text"] \
        [--title-duration 3]

Requires: ffmpeg, ffprobe on PATH
"""

import argparse
import os
import subprocess
import sys
import tempfile


def get_env(key, default):
    return os.environ.get(key, default)


# Defaults from environment or hardcoded
VIDEO_WIDTH = get_env("VIDEO_WIDTH", "1080")
VIDEO_HEIGHT = get_env("VIDEO_HEIGHT", "1920")
VIDEO_FPS = get_env("VIDEO_FPS", "30")
VIDEO_CRF = get_env("VIDEO_CRF", "23")
FONT_PATH = get_env("FONT_PATH", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
FONT_SIZE = get_env("FONT_SIZE", "48")
FFMPEG_BIN = get_env("FFMPEG_BIN", "ffmpeg")
FFPROBE_BIN = get_env("FFPROBE_BIN", "ffprobe")


def run_cmd(cmd, description=""):
    """Run a shell command and exit on failure."""
    if description:
        print(f"  {description}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running: {' '.join(cmd)}", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def get_audio_duration(audio_path):
    """Get duration of audio file in seconds."""
    output = run_cmd([
        FFPROBE_BIN, "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        audio_path
    ], "Getting audio duration")
    return float(output)


def escape_subtitles_path(path):
    """Escape subtitle path for FFmpeg filter syntax."""
    return path.replace("\\", "\\\\").replace(":", "\\:").replace("'", "\\'")


def render_title_card(title_text, duration, output_path):
    """Render a simple title card: dark background with centered white text."""
    cmd = [
        FFMPEG_BIN, "-y",
        "-f", "lavfi", "-i",
        f"color=c=0x1a1a2e:s={VIDEO_WIDTH}x{VIDEO_HEIGHT}:d={duration}:r={VIDEO_FPS}",
        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
        "-vf",
        f"drawtext=text='{title_text}':fontfile={FONT_PATH}:fontsize=64"
        f":fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:line_spacing=20",
        "-c:v", "libx264", "-preset", "medium", "-crf", VIDEO_CRF,
        "-c:a", "aac", "-b:a", "128k",
        "-t", str(duration),
        output_path
    ]
    run_cmd(cmd, "Rendering title card")


def render_main_video(background, audio, subtitles, duration, output_path):
    """Render the main video: static background + audio + burned subtitles."""
    subs_escaped = escape_subtitles_path(subtitles)
    subtitle_style = (
        "FontSize=14,FontName=DejaVu Sans Bold,"
        "PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,"
        "BorderStyle=3,Outline=1,Shadow=0,MarginL=40,MarginR=40,MarginV=80,"
        "Alignment=2,BackColour=&H80000000,WrapStyle=1"
    )

    cmd = [
        FFMPEG_BIN, "-y",
        "-loop", "1", "-i", background,
        "-i", audio,
        "-vf",
        f"scale={VIDEO_WIDTH}:{VIDEO_HEIGHT}:force_original_aspect_ratio=decrease,"
        f"pad={VIDEO_WIDTH}:{VIDEO_HEIGHT}:(ow-iw)/2:(oh-ih)/2,"
        f"subtitles={subs_escaped}:force_style='{subtitle_style}'",
        "-c:v", "libx264", "-preset", "medium", "-crf", VIDEO_CRF,
        "-tune", "stillimage",
        "-c:a", "aac", "-b:a", "128k",
        "-r", VIDEO_FPS,
        "-shortest",
        "-movflags", "+faststart",
        "-t", str(duration),
        output_path
    ]
    run_cmd(cmd, "Rendering main video")


def concatenate_videos(video_paths, output_path):
    """Concatenate multiple videos using FFmpeg concat demuxer."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        for path in video_paths:
            f.write(f"file '{path}'\n")
        concat_list = f.name

    try:
        run_cmd([
            FFMPEG_BIN, "-y",
            "-f", "concat", "-safe", "0",
            "-i", concat_list,
            "-c", "copy",
            "-movflags", "+faststart",
            output_path
        ], "Concatenating segments")
    finally:
        os.unlink(concat_list)


def main():
    parser = argparse.ArgumentParser(description="Render a vertical short-form video")
    parser.add_argument("--background", required=True, help="Path to background image")
    parser.add_argument("--audio", required=True, help="Path to voiceover audio file")
    parser.add_argument("--subtitles", required=True, help="Path to SRT subtitle file")
    parser.add_argument("--output", required=True, help="Output MP4 path")
    parser.add_argument("--title", default="", help="Title card text (optional)")
    parser.add_argument("--title-duration", type=int, default=3, help="Title card duration in seconds")
    args = parser.parse_args()

    # Validate input files
    for path in [args.background, args.audio, args.subtitles]:
        if not os.path.isfile(path):
            print(f"Error: File not found: {path}", file=sys.stderr)
            sys.exit(1)

    # Ensure output directory exists
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)

    audio_duration = get_audio_duration(args.audio)
    print(f"Audio duration: {audio_duration:.1f}s")

    if args.title:
        # Two-pass: title card + main video
        with tempfile.TemporaryDirectory() as tmpdir:
            title_path = os.path.join(tmpdir, "title_card.mp4")
            main_path = os.path.join(tmpdir, "main_video.mp4")

            render_title_card(args.title, args.title_duration, title_path)
            render_main_video(args.background, args.audio, args.subtitles, audio_duration, main_path)
            concatenate_videos([title_path, main_path], args.output)
    else:
        render_main_video(args.background, args.audio, args.subtitles, audio_duration, args.output)

    # Report final duration
    final_duration = get_audio_duration(args.output)
    print(f"Done: {args.output}")
    print(f"Final duration: {final_duration:.1f}s")


if __name__ == "__main__":
    main()
