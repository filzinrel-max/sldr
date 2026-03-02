# LSL Modules

Primary runtime scripts:
- [sldr_game_main.lsl](/C:/Users/Michael/source/repos/sldr/lsl/core/sldr_game_main.lsl) (orchestrator: sit/session/UI/input permissions; reads play request from media URL)
- [sldr_game_runtime.lsl](/C:/Users/Michael/source/repos/sldr/lsl/core/sldr_game_runtime.lsl) (chart fetch/parse/judge/render/score)

Included modules:
- [ddr_state_machine.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_state_machine.lslh)
- [ddr_chart_data_loader.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_chart_data_loader.lslh)
- [ddr_combo_feedback.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_combo_feedback.lslh)
- [ddr_scoring.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_scoring.lslh)
- [ddr_judge_feedback.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_judge_feedback.lslh)
- [ddr_judgement.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_judgement.lslh)
- [ddr_lane_renderer.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_lane_renderer.lslh)
- [ddr_animation_bridge.lslh](/C:/Users/Michael/source/repos/sldr/lsl/core/ddr_animation_bridge.lslh)

Shared include layer:
- [ddr_config.lslh](/C:/Users/Michael/source/repos/sldr/lsl/include/ddr_config.lslh)
- [ddr_constants.lslh](/C:/Users/Michael/source/repos/sldr/lsl/include/ddr_constants.lslh)
- [ddr_debug.lslh](/C:/Users/Michael/source/repos/sldr/lsl/include/ddr_debug.lslh)
- [ddr_link_messages.lslh](/C:/Users/Michael/source/repos/sldr/lsl/include/ddr_link_messages.lslh)

Test/utility scripts:
- [arrow_slide_test.lsl](/C:/Users/Michael/source/repos/sldr/lsl/tools/arrow_slide_test.lsl)
- [lane_stack_generator.lsl](/C:/Users/Michael/source/repos/sldr/lsl/tools/lane_stack_generator.lsl)

## Firestorm Preprocessor

Both runtime scripts use `#include` paths relative to `lsl/core/`.

Load/compile:
1. compile [sldr_game_main.lsl](/C:/Users/Michael/source/repos/sldr/lsl/core/sldr_game_main.lsl) with Firestorm preprocessing enabled
2. compile [sldr_game_runtime.lsl](/C:/Users/Michael/source/repos/sldr/lsl/core/sldr_game_runtime.lsl) with Firestorm preprocessing enabled
3. ensure include files are available at their referenced relative paths
4. ensure both are compiled as `Mono` (not LSO)

## Arrow Slide Test

Use [arrow_slide_test.lsl](/C:/Users/Michael/source/repos/sldr/lsl/tools/arrow_slide_test.lsl) to validate stacked-slot arrow scrolling on a linked set.
This version uses client-side `llSetLinkTextureAnim` for smoother motion.

Quick setup:
1. drop script into root prim
2. set `START_LINK`/`END_LINK` to the 10 stacked arrow prim links
3. set `ARROW_TEXTURE` to your arrow texture name/UUID
4. tune:
   - `TRAVEL_SECONDS` (arrow bottom->top time)
   - `SPAWN_INTERVAL` (new arrow cadence, use `0.10` for 10 concurrent over 1 second)
   - `TICK_SECONDS` (spawn/cleanup cadence only; motion is client-side)
   - `TEXTURE_ROTATE_DEGREES` (set `90.0` for quarter-turn rotation)
   - animation direction:
     - `ANIM_REVERSE = TRUE` for upward travel in the default setup
     - if direction is wrong, flip `ANIM_REVERSE`
   - spawn position tuning:
     - adjust `ANIM_START` and `ANIM_LENGTH` (defaults `1.0`, `1.0`)

## Lane Stack Generator

Use [lane_stack_generator.lsl](/C:/Users/Michael/source/repos/sldr/lsl/tools/lane_stack_generator.lsl) as a rez/link utility.

Workflow:
1. Rez the generator object.
2. Put one or more lane template **OBJECTS** in its inventory.
3. Click the generator (owner only).
4. For each template object, it creates and links:
   - `{templateName}_01` ... `{templateName}_10`

Notes:
- Generated prims link to the generator object (generator stays root).
- If you include 4 templates (left/down/up/right), it builds 4 stacks.
- `TEMPLATE_GROUP_SPACING` in the script controls spacing between template stacks.

## Player Flow (Sit to Dance)

1. Player right-clicks the machine and selects `Dance` (sit text).
2. On sit, script starts a session for that avatar.
3. Session enters `Splash`, then auto-moves to `Main Menu`.
4. `menu.html` fetches `game-data/song-manifest.lsl.json` and renders song+difficulty selection.
5. When user presses `Play`, web UI writes selection into media URL query:
   - `cmd=play`
   - `song`
   - `title`
   - `artist`
   - `difficulty`
   - `chart` (relative chart JSON path)
   - `req` (unique request id)
6. LSL detects the URL request and starts gameplay by loading only that selected chart JSON.
7. If player stands, session ends immediately and machine returns to idle splash.

Prerequisite for gameplay:
1. run `python tools/build_song_manifest.py`
2. run `python tools/build_song_charts.py`

## Owner Command Channel

Use `/9919` commands (owner only):
- `/9919 debug on`
- `/9919 debug off`
- `/9919 reload`
- `/9919 menu`
- `/9919 play <chartPathOrUrl> [difficulty] [songId]`
- `/9919 stop`
- `/9919 status`

## Configuration

Edit [ddr_config.lslh](/C:/Users/Michael/source/repos/sldr/lsl/include/ddr_config.lslh):
- `DDR_BASE_URL`
- sit behavior:
  - `DDR_SIT_TEXT`
  - `DDR_SIT_TARGET_OFFSET`
  - `DDR_SIT_TARGET_ROT`
- judgement windows
- scoring weights
- lane animation names
- lane renderer (stacked prim texture animation):
  - `DDR_ARROW_FACE`
  - `DDR_ARROW_SLOTS_PER_LANE`
  - `DDR_LANE_LINK_PREFIXES` (`LEFT`, `DOWN`, `UP`, `RIGHT` order)
  - `DDR_LANE_ARROW_TEXTURES` (`LEFT`, `DOWN`, `UP`, `RIGHT` order)
  - `DDR_ARROW_TEXTURE_ROTATE_DEGREES`
  - `DDR_ARROW_ANIM_START`
  - `DDR_ARROW_ANIM_LENGTH`
  - `DDR_ARROW_ANIM_REVERSE`
  - `DDR_ARROW_TRAVEL_SECONDS`
  - Prim naming convention:
    - `ARROW_LANE_LEFT_01` ... `_10`
    - `ARROW_LANE_DOWN_01` ... `_10`
    - `ARROW_LANE_UP_01` ... `_10`
    - `ARROW_LANE_RIGHT_01` ... `_10`
- combo popup prim and text behavior:
  - `DDR_COMBO_FEEDBACK_LINK`
  - `DDR_COMBO_FEEDBACK_SECONDS`
  - `DDR_COMBO_FEEDBACK_MIN_COMBO`
  - `DDR_COMBO_FEEDBACK_ALPHA`
  - `DDR_COMBO_COLOR_LOW`
  - `DDR_COMBO_COLOR_MID`
  - `DDR_COMBO_COLOR_HIGH`
  - `DDR_COMBO_COLOR_MAX`
- judgement feedback prim and textures:
  - `DDR_JUDGE_FEEDBACK_LINK`
  - `DDR_JUDGE_FEEDBACK_FACE`
  - `DDR_JUDGE_FEEDBACK_SECONDS`
  - `DDR_JUDGE_FEEDBACK_TEXTURES` order:
    - `PERFECT`, `GREAT`, `GOOD`, `BOO`, `MISS`, `HOLD_OK`, `HOLD_NG`
