# Web Screens

These pages are loaded on the media texture by `lsl/core/sldr_game_main.lsl`.

## Query Contracts

`splash.html`
- `status`
- `error` (optional)
- auto-redirects to `menu.html` after ~5 seconds

`menu.html`
- LSL-provided optional:
  - `error`
- UI behavior:
  - shows `SLDR` title + `Press Start`
  - button navigates to `select.html`

`select.html`
- LSL-provided optional:
  - `song` (selected song id hint)
  - `difficulty` (selected difficulty hint)
  - `error` (optional, if previous runtime request failed)
- Web->LSL play request query (written by `select.html` itself):
  - `cmd=play`
  - `req` (unique token to avoid replay)
  - `song`
  - `title`
  - `artist`
  - `difficulty`
  - `chart` (relative chart JSON path, e.g. `game-data/charts/<song>/<difficulty>.chart.json`)
  - `media` (optional relative media path)

`play.html`
- `loading` (`0|1`)
- `id`
- `title`
- `artist`
- `difficulty`
- `meter`
- `media` (optional relative/absolute media URL; usually `*.mp4` with song audio)

`score.html`
- `result` (escaped JSON payload from LSL)

## Score Payload Fields

Expected JSON (from LSL):
- `songId`
- `title`
- `artist`
- `difficulty`
- `meter`
- `score`
- `percent`
- `grade`
- `comboMax`
- `judgements.perfect|great|good|boo|miss`
- `holds.ok|ng`
- `radar.song` (5-item array)
- `radar.performance` (5-item array)
