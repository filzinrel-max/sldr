# SLDR Design Specification

## 1) Goal

Build a maintainable, single-player DDR-style game in Second Life using:
- StepMania song/chart files from `songs/`
- HTML screens shown on a media texture (GitHub-hosted pages)
- in-world arrow rendering with pooled prims (4 lanes x 10 slots each)
- LSL gameplay and judging logic

The design supports:
- single notes
- simultaneous notes (jumps/chords, including `left + right`)
- holds
- end-of-song grading (A-F)
- DDR radar chart on results screen

Scope limit:
- parse and play `dance-single` charts only.

## 2) Constraints and Assumptions

1. Runtime is Second Life + LSL script limits.
2. Assets are hosted in GitHub repository / GitHub Pages.
3. LSL fetches remote text assets with `llHTTPRequest`.
4. LSL HTTP response body practical limit is about 16KB, so startup manifest should be compact.
5. Firestorm preprocessor directives are available for LSL source organization.
6. User already has button-press animations that must be triggered from gameplay input events.

## 3) High-Level Architecture

## 3.1 Runtime Components

1. **In-world object (LSL)**:
   - state machine (splash, menu, select, play, score)
   - input capture
   - chart timing, judgement, combo, scoring
   - prim-pool arrow rendering
   - animation trigger bridge
   - song/manifest HTTP loading

2. **Media texture web UI (GitHub-hosted HTML/JS/CSS)**:
   - visual screens
   - song art and metadata display
   - score/radar rendering
   - optional loading/progress indicators

3. **Offline content pipeline (local scripts)**:
   - song manifest generation
   - OGG -> MP3 conversion
   - AVI + MP3 -> MP4 generation
   - fallback MP4 generation from BG PNG + MP3

## 3.2 Data Flow

1. Build pipeline generates:
   - `game-data/song-manifest.json` (full)
   - `game-data/song-manifest.lsl.json` (compact for LSL startup)
2. On game startup, LSL downloads compact manifest from GitHub.
3. Song select uses manifest metadata.
4. When player starts a song, LSL downloads the song `.sm` file and parses `dance-single` chart for selected difficulty.
5. Gameplay runs locally in LSL (judgement and score are authoritative).
6. Results are sent to score screen via URL params or compact JSON payload in query string/hash.

## 4) Repository Layout (Target)

```text
docs/
  ddr-secondlife-design-spec.md
game-data/
  song-manifest.json
  song-manifest.lsl.json
lsl/
  include/
    ddr_config.lslh
    ddr_debug.lslh
    ddr_constants.lslh
  core/
    ddr_state_machine.lsl
    ddr_http_loader.lsl
    ddr_chart_parser.lsl
    ddr_lane_renderer.lsl
    ddr_input_router.lsl
    ddr_judgement.lsl
    ddr_scoring.lsl
    ddr_animation_bridge.lsl
web/
  splash.html
  menu.html
  select.html
  play.html
  score.html
tools/
  _songlib.py
  build_song_manifest.py
  convert_ogg_to_mp3.py
  build_song_videos.py
songs/
  <Song Name>/
    *.sm
    *.ogg
    *-bg.png
    optional *.avi
```

## 5) State Machine

States:
1. `SPLASH`
2. `MAIN_MENU`
3. `SONG_SELECT`
4. `PLAYING`
5. `SCORE`

Transitions:
1. `SPLASH -> MAIN_MENU` after preload complete or timeout.
2. `MAIN_MENU -> SONG_SELECT` on start input.
3. `SONG_SELECT -> PLAYING` when song + difficulty selected and chart parsed.
4. `PLAYING -> SCORE` at chart end + hold resolution.
5. `SCORE -> MAIN_MENU` on continue/timeout.

Each transition updates media URL on display prim and emits optional debug log events.

## 6) Screen Responsibilities

1. `splash.html`:
   - show loading/progress
   - no game interaction required

2. `menu.html`:
   - single-player start entry point

3. `select.html`:
   - reads manifest
   - shows song metadata + difficulty options

4. `play.html`:
   - shows now-playing metadata/timer/combo
   - optional background video/media framing
   - arrow timing remains LSL-authoritative

5. `score.html`:
   - shows final score, grade A-F, counts, max combo
   - renders DDR radar chart axes (Stream, Voltage, Air, Freeze, Chaos)

## 7) Chart Parsing Rules (`.sm`)

1. Read song-level tags:
   - `#TITLE`, `#ARTIST`, `#MUSIC`, `#BANNER`, `#BACKGROUND`, `#BPMS`, `#OFFSET`, `#BGCHANGES`
2. Parse all `#NOTES:` blocks.
3. Keep only blocks with `step_type == dance-single`.
4. For selected difficulty, parse measure rows:
   - commas separate measures
   - each measure row has 4 columns (L,D,U,R)
5. Supported note symbols:
   - `1`: tap
   - `2`: hold start
   - `3`: hold end
   - `4`: roll start (treat as hold-like unless custom behavior added)
   - `0`: empty

Lane mapping:
- index `0=Left`, `1=Down`, `2=Up`, `3=Right`.

## 8) Prim-Pool Arrow Renderer

Configuration:
1. 4 lanes.
2. 10 reusable arrow prim slots per lane.
3. total note slots = 40.

Runtime behavior:
1. Maintain a moving look-ahead window (example: 2.5 to 3.0 seconds).
2. Collect upcoming notes per lane.
3. Assign notes to free slot prims in that lane.
4. Set per-slot:
   - alpha (0 hidden / 1 visible)
   - texture frame/type (tap, hold-head, hold-tail indicator)
   - local position based on time-to-target
5. Recycle slot as soon as note exits miss window or is consumed.

Benefits:
1. avoids rez/delete overhead
2. deterministic script cost
3. stable visuals with bounded prim count

## 9) Input and Judgement

Input requirements:
1. single direction presses
2. combos/chords (example `left + right`)
3. holds (press + release tracking)

Recommended update cadence:
- timer tick around 20Hz to 40Hz (0.05s to 0.025s), tuned by script time budget.

Judgement windows (initial tuning set):
1. `PERFECT`: <= 45 ms
2. `GREAT`: <= 90 ms
3. `GOOD`: <= 135 ms
4. `BOO`: <= 180 ms
5. `MISS`: > 180 ms or not hit before late bound

Holds:
1. hold starts are judged like tap notes.
2. hold success requires lane pressed through hold body until release zone.
3. early release counts as `Hold NG`.

## 10) Scoring Model

Recommended point model:
1. `PERFECT`: +3
2. `GREAT`: +2
3. `GOOD`: +1
4. `BOO`: +0
5. `MISS`: -4
6. `Hold OK`: +2
7. `Hold NG`: -2

Derived metrics:
1. total score
2. combo / max combo
3. judgement counts
4. percentage = `max(0, earned_points / max_possible_points)`

Grade mapping (A-F):
1. `A`: >= 93%
2. `B`: >= 80%
3. `C`: >= 65%
4. `D`: >= 45%
5. `E`: >= 30%
6. `F`: < 30%

These thresholds are configurable in shared config macros.

## 11) DDR Radar Chart

Axes:
1. Stream
2. Voltage
3. Air
4. Freeze
5. Chaos

Chart difficulty radar (from chart structure):
1. Stream: average note density
2. Voltage: peak short-window note density
3. Air: jump/chord frequency
4. Freeze: hold note frequency
5. Chaos: irregular subdivision/off-grid density

Performance radar (player run):
1. Stream: sustained hit ratio across song
2. Voltage: best high-density section accuracy
3. Air: chord hit rate
4. Freeze: hold completion ratio
5. Chaos: off-beat note hit rate

Result screen shows one or both polygons (song profile + performance profile).

## 12) Animation Integration

Animation bridge rules:
1. input router emits logical events (`PRESS_LEFT`, `PRESS_UP`, etc.).
2. animation bridge maps events to existing animation names.
3. support simultaneous triggers for chords when allowed by animation set.
4. keep animation trigger logic separate from scoring logic to avoid coupling.

## 13) Debug Strategy (Global Toggle via Firestorm Preprocessor)

Use compile-time flags in shared include file.

Example pattern:

```c
// ddr_debug.lslh
#ifndef DDR_DEBUG
#define DDR_DEBUG 0
#endif

#if DDR_DEBUG
    #define DBG(MSG) llOwnerSay("[SLDR] " + (string)(MSG))
#else
    #define DBG(MSG)
#endif
```

Guidelines:
1. all scripts include `ddr_debug.lslh`.
2. logs are structured with short prefixes (`STATE`, `HTTP`, `JUDGE`, `RENDER`).
3. debug-only expensive traces are wrapped behind compile flag.

## 14) HTTP and GitHub Hosting Strategy

1. Host static web screens and generated JSON in GitHub Pages/repo.
2. LSL startup fetches compact manifest:
   - `game-data/song-manifest.lsl.json`
3. On song load, LSL fetches chosen `.sm`.
4. Media URLs are built from manifest paths and a configured base URL.
5. Cache chart/metadata in script memory during a run.

Fallback/error behavior:
1. if manifest fetch fails, show error in splash/menu and retry.
2. if song chart fetch fails, return to song select with message.
3. if video file missing, play PNG-based MP4 fallback.

## 15) Tooling Pipeline (Implemented)

1. `tools/build_song_manifest.py`
   - scans `songs/*`
   - parses `.sm` metadata + `dance-single` chart summaries
   - emits:
     - full: `game-data/song-manifest.json`
     - compact: `game-data/song-manifest.lsl.json`
   - emits paged compact files automatically when compact payload exceeds configured LSL-safe size

2. `tools/convert_ogg_to_mp3.py`
   - converts per-song `.ogg` to `.mp3` via `ffmpeg`
   - supports dry-run and skip-existing

3. `tools/build_song_videos.py`
   - builds `.mp4` from:
     - preferred: `.avi + .mp3`
     - fallback: `*-bg.png + .mp3`
   - supports dry-run and skip-existing

## 16) Maintainability Rules

1. Keep gameplay logic split by responsibility:
   - parser, renderer, input, scoring, state machine.
2. Use shared constants include for:
   - lanes
   - judgement windows
   - grade thresholds
   - URLs
3. Keep deterministic data contracts:
   - manifest schema versioned
   - score payload schema versioned
4. Avoid hardcoded song names or paths in scripts.
5. Write scripts with explicit CLI flags and safe defaults.

## 17) Implementation Milestones

1. **M1: Data + hosting**
   - finalize manifest generation
   - publish web skeleton pages

2. **M2: LSL core loop**
   - state machine + HTTP loader
   - parse selected single chart and schedule notes

3. **M3: Renderer + input**
   - 4x10 prim pool arrow rendering
   - single/chord/hold handling
   - animation triggers

4. **M4: Judgement + scoring**
   - combo and grade A-F
   - results payload

5. **M5: Results UI**
   - radar chart + judgement breakdown
   - polish and debug instrumentation

## 18) Open Technical Decisions

1. Final judgement window tuning for simulator latency.
2. Exact media/audio sync mechanism between LSL timer and browser playback.
3. Whether to keep results persistence local-only or add external storage later.
4. Preferred resolution/bitrate for MP4 files for media texture performance.
