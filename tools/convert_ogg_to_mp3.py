#!/usr/bin/env python3
"""Convert song OGG files to MP3 with ffmpeg."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

from _songlib import list_song_dirs, pick_preferred_file


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--songs-root", default="songs", help="Path to song folders")
    parser.add_argument("--ffmpeg-bin", default="ffmpeg", help="ffmpeg executable name/path")
    parser.add_argument("--bitrate", default="192k", help="Output MP3 bitrate (default: 192k)")
    parser.add_argument("--skip-existing", action="store_true", help="Skip when target MP3 exists")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    parser.add_argument("--limit", type=int, default=0, help="Optional max songs to process")
    return parser.parse_args()


def ensure_ffmpeg(ffmpeg_bin: str) -> None:
    if shutil.which(ffmpeg_bin):
        return
    raise SystemExit(f"ffmpeg not found on PATH: {ffmpeg_bin}")


def build_command(ffmpeg_bin: str, source: Path, target: Path, bitrate: str) -> list[str]:
    return [
        ffmpeg_bin,
        "-y",
        "-i",
        str(source),
        "-vn",
        "-c:a",
        "libmp3lame",
        "-b:a",
        bitrate,
        str(target),
    ]


def main() -> int:
    args = parse_args()
    songs_root = Path(args.songs_root).resolve()
    if not songs_root.exists() or not songs_root.is_dir():
        raise SystemExit(f"songs root not found: {songs_root}")

    if not args.dry_run:
        ensure_ffmpeg(args.ffmpeg_bin)

    converted = 0
    skipped = 0
    failed = 0
    processed = 0

    for song_dir in list_song_dirs(songs_root):
        if args.limit > 0 and processed >= args.limit:
            break
        processed += 1

        source = pick_preferred_file(song_dir, ".ogg")
        if not source:
            print(f"[skip] {song_dir.name}: no .ogg found")
            skipped += 1
            continue
        target = source.with_suffix(".mp3")

        if args.skip_existing and target.exists():
            print(f"[skip] {song_dir.name}: already has {target.name}")
            skipped += 1
            continue

        cmd = build_command(args.ffmpeg_bin, source, target, args.bitrate)
        print(f"[run] {song_dir.name}: {' '.join(cmd)}")
        if args.dry_run:
            converted += 1
            continue

        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            converted += 1
            continue

        failed += 1
        print(f"[fail] {song_dir.name}: ffmpeg exit {result.returncode}")
        if result.stderr:
            print(result.stderr.strip().splitlines()[-1])

    print(
        f"Done. converted={converted} skipped={skipped} failed={failed} processed={processed}"
        + (" (dry-run)" if args.dry_run else "")
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

