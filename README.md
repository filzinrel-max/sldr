# SLDR (Second Life DDR)

Second Life single-player DDR implementation using:
- StepMania `.sm` charts (`dance-single` only)
- media-on-a-prim HTML screens hosted on GitHub
- in-world prim-based arrow rendering (no arrow rezzing)

## Repository Status

This repository is initialized and includes:
- detailed system design spec: `docs/ddr-secondlife-design-spec.md`
- LSL runtime modules + main script: `lsl/`
- media-texture screen pages: `web/`
- build scripts:
  - `tools/build_song_manifest.py`
  - `tools/build_song_charts.py`
  - `tools/convert_ogg_to_mp3.py`
  - `tools/build_song_videos.py`

## Requirements

- Python 3.10+
- `ffmpeg` on PATH (for audio/video conversion scripts)

## Quick Start

Generate manifest files:

```bash
python tools/build_song_manifest.py --base-url "https://<user>.github.io/<repo>"
```

Prebuild compact per-difficulty chart JSON (for in-world LSL runtime):

```bash
python tools/build_song_charts.py
```

Convert all OGG files to MP3:

```bash
python tools/convert_ogg_to_mp3.py --skip-existing
```

Build MP4 for each song:
- uses `*.avi + *.mp3` when AVI exists
- falls back to `*-bg.png + *.mp3` when AVI is missing

```bash
python tools/build_song_videos.py --skip-existing
```

## Notes

- Generated MP3/MP4 files are ignored in Git by default (see `.gitignore`).
- To commit locally generated media, use force-add:
  - `git add -f songs/**/*.mp3 songs/**/*.mp4`
- Manifest includes both full JSON and compact JSON for web menu usage.
- LSL runtime does not load the song manifest; `web/menu.html` reads manifest and sends selected chart path via media URL query.
- Compact manifest target size is checked against the ~16KB LSL HTTP body limit.
- If compact output exceeds `--lsl-max-bytes`, paged LSL files are emitted automatically.
