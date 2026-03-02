# Tools

## 1) Build Song Manifests

```bash
python tools/build_song_manifest.py --base-url "https://<user>.github.io/<repo>"
```

Outputs:
- `game-data/song-manifest.json` (full)
- `game-data/song-manifest.lsl.json` (compact for LSL startup fetch)

## 2) Build Preparsed Chart JSON

```bash
python tools/build_song_charts.py
```

Outputs:
- `game-data/charts/<song_id>/<difficulty>.chart.json` (compact prebuilt chart payloads)
- updates `game-data/song-manifest.json` and `game-data/song-manifest.lsl.json` with chart-path mappings

## 3) Convert OGG to MP3

```bash
python tools/convert_ogg_to_mp3.py --skip-existing
```

Helpful options:
- `--dry-run`
- `--limit 5`

## 4) Build MP4 Song Videos

```bash
python tools/build_song_videos.py --skip-existing
```

Behavior:
- prefers `AVI + MP3`
- falls back to `*-bg.png + MP3` when AVI is unavailable
- encodes audio as `AAC-LC 44.1kHz stereo` for SL compatibility
- with `--skip-existing`, verifies each existing MP4 has an audio stream and rebuilds if missing

Helpful options:
- `--dry-run`
- `--limit 5`
- `--size 1280x720`
- `--use-ogg-if-mp3-missing`
- `--trust-existing-audio` (skip audio-stream verification when using `--skip-existing`)
