#!/usr/bin/env python3
"""Build MP4 song videos from AVI+MP3, or BG PNG + MP3 when AVI is missing."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

from _songlib import extract_tag, list_song_dirs, parse_bgchanges_first_avi, pick_preferred_file, read_text_file


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--songs-root", default="songs", help="Path to song folders")
    parser.add_argument("--ffmpeg-bin", default="ffmpeg", help="ffmpeg executable name/path")
    parser.add_argument("--size", default="1280x720", help="Output video size WIDTHxHEIGHT")
    parser.add_argument("--fps", default="30", help="Output frame rate")
    parser.add_argument("--crf", default="22", help="Video quality CRF for libx264")
    parser.add_argument("--preset", default="medium", help="libx264 preset")
    parser.add_argument("--audio-bitrate", default="192k", help="AAC audio bitrate")
    parser.add_argument("--skip-existing", action="store_true", help="Skip when target MP4 exists")
    parser.add_argument(
        "--trust-existing-audio",
        action="store_true",
        help="When used with --skip-existing, do not verify that existing MP4 has an audio stream",
    )
    parser.add_argument("--use-ogg-if-mp3-missing", action="store_true", help="Allow OGG as audio fallback")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    parser.add_argument("--limit", type=int, default=0, help="Optional max songs to process")
    return parser.parse_args()


def ensure_ffmpeg(ffmpeg_bin: str) -> None:
    if shutil.which(ffmpeg_bin):
        return
    raise SystemExit(f"ffmpeg not found on PATH: {ffmpeg_bin}")


def has_audio_stream(ffmpeg_bin: str, media_file: Path) -> bool:
    probe_cmd = [
        ffmpeg_bin,
        "-v",
        "error",
        "-i",
        str(media_file),
        "-map",
        "0:a:0",
        "-f",
        "null",
        "-",
    ]
    result = subprocess.run(probe_cmd, capture_output=True, text=True, check=False)
    return result.returncode == 0


def find_audio_source(song_dir: Path, use_ogg_if_missing: bool) -> Path | None:
    mp3 = pick_preferred_file(song_dir, ".mp3")
    if mp3:
        return mp3
    if use_ogg_if_missing:
        return pick_preferred_file(song_dir, ".ogg")
    return None


def find_video_source(song_dir: Path) -> Path | None:
    sm_file = pick_preferred_file(song_dir, ".sm")
    if sm_file:
        sm_text = read_text_file(sm_file)
        bgchanges = extract_tag(sm_text, "BGCHANGES")
        bgchanges_avi = parse_bgchanges_first_avi(bgchanges, song_dir)
        if bgchanges_avi:
            return bgchanges_avi

    fallback_avi = pick_preferred_file(song_dir, ".avi")
    if fallback_avi:
        return fallback_avi

    bg_candidates = sorted(song_dir.glob("*-bg.png"), key=lambda p: p.name.lower())
    return bg_candidates[0] if bg_candidates else None


def command_for_avi(
    ffmpeg_bin: str,
    source_video: Path,
    source_audio: Path,
    target: Path,
    fps: str,
    crf: str,
    preset: str,
    audio_bitrate: str,
) -> list[str]:
    return [
        ffmpeg_bin,
        "-y",
        "-i",
        str(source_video),
        "-i",
        str(source_audio),
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-r",
        fps,
        "-c:v",
        "libx264",
        "-preset",
        preset,
        "-crf",
        crf,
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-ac",
        "2",
        "-ar",
        "44100",
        "-b:a",
        audio_bitrate,
        "-movflags",
        "+faststart",
        "-shortest",
        str(target),
    ]


def command_for_png(
    ffmpeg_bin: str,
    source_image: Path,
    source_audio: Path,
    target: Path,
    size: str,
    fps: str,
    crf: str,
    preset: str,
    audio_bitrate: str,
) -> list[str]:
    width, height = size.split("x", 1)
    scale_filter = (
        f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
        f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2"
    )
    return [
        ffmpeg_bin,
        "-y",
        "-loop",
        "1",
        "-i",
        str(source_image),
        "-i",
        str(source_audio),
        "-r",
        fps,
        "-vf",
        scale_filter,
        "-c:v",
        "libx264",
        "-preset",
        preset,
        "-crf",
        crf,
        "-tune",
        "stillimage",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-ac",
        "2",
        "-ar",
        "44100",
        "-b:a",
        audio_bitrate,
        "-movflags",
        "+faststart",
        "-shortest",
        str(target),
    ]


def main() -> int:
    args = parse_args()
    songs_root = Path(args.songs_root).resolve()
    if not songs_root.exists() or not songs_root.is_dir():
        raise SystemExit(f"songs root not found: {songs_root}")

    if "x" not in args.size:
        raise SystemExit("--size must be in WIDTHxHEIGHT format (example: 1280x720)")

    if not args.dry_run:
        ensure_ffmpeg(args.ffmpeg_bin)

    built = 0
    skipped = 0
    failed = 0
    processed = 0

    for song_dir in list_song_dirs(songs_root):
        if args.limit > 0 and processed >= args.limit:
            break
        processed += 1

        audio_source = find_audio_source(song_dir, args.use_ogg_if_mp3_missing)
        if not audio_source:
            print(f"[skip] {song_dir.name}: no MP3 found (or OGG fallback disabled)")
            skipped += 1
            continue

        video_source = find_video_source(song_dir)
        if not video_source:
            print(f"[skip] {song_dir.name}: no AVI or *-bg.png source found")
            skipped += 1
            continue

        target = audio_source.with_suffix(".mp4")
        if args.skip_existing and target.exists():
            skip_existing = True
            if not args.trust_existing_audio:
                if has_audio_stream(args.ffmpeg_bin, target):
                    print(f"[skip] {song_dir.name}: already has {target.name} (audio ok)")
                else:
                    print(f"[rebuild] {song_dir.name}: existing {target.name} has no audio stream")
                    skip_existing = False
            else:
                print(f"[skip] {song_dir.name}: already has {target.name}")
            if skip_existing:
                skipped += 1
                continue

        if video_source.suffix.lower() == ".png":
            cmd = command_for_png(
                args.ffmpeg_bin,
                source_image=video_source,
                source_audio=audio_source,
                target=target,
                size=args.size,
                fps=args.fps,
                crf=args.crf,
                preset=args.preset,
                audio_bitrate=args.audio_bitrate,
            )
            source_kind = "png+audio"
        else:
            cmd = command_for_avi(
                args.ffmpeg_bin,
                source_video=video_source,
                source_audio=audio_source,
                target=target,
                fps=args.fps,
                crf=args.crf,
                preset=args.preset,
                audio_bitrate=args.audio_bitrate,
            )
            source_kind = "avi+audio"

        print(f"[run] {song_dir.name} ({source_kind}): {' '.join(cmd)}")
        if args.dry_run:
            built += 1
            continue

        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            built += 1
            continue

        failed += 1
        print(f"[fail] {song_dir.name}: ffmpeg exit {result.returncode}")
        if result.stderr:
            print(result.stderr.strip().splitlines()[-1])

    print(
        f"Done. built={built} skipped={skipped} failed={failed} processed={processed}"
        + (" (dry-run)" if args.dry_run else "")
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
