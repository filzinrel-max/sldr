# Web Screens

These pages are loaded on the media texture by `lsl/core/sldr_game_main.lsl`.

## Query Contracts

`splash.html`
- `status`
- `error` (optional)
- no auto-navigation; LSL controls the next page

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
  - `chart` (relative chart index path, e.g. `game-data/charts/<song>/<difficulty>.chart.idx.json`)
  - `media` (optional relative media path)
  - request is sent by navigating to `loading.html` with those query fields

`loading.html`
- receives the same play request query fields from `select.html`
- displays loading interstitial while LSL reads the media URL and transitions to `play.html`

`play.html`
- `loading` (`0|1`)
- `id`
- `title`
- `artist`
- `difficulty`
- `meter`
- `media` (optional relative/absolute media URL; usually `*.mp4` with song audio)
- behavior: full-page MP4/video playback using `media` (UI overlays removed)

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
