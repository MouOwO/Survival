Difficulty selection: five official Dota 2 material concepts

Run from repository root:
  node tools/difficulty_native_20261019/run.cjs
  node tools/difficulty_native_20261019/run.cjs --build-only

The archived helpers are the exact sources used for the verified local captures.
run.cjs stages them under output/ui_native_finish_20261019, freezes the current
survival_ui.js and archive_difficulty.css, and runs the actual production XML/JS/CSS
through the existing browser adapter. It never modifies production sources.

Native texture records preserve installed Valve VPK and decoded PNG SHA256 values.
Missing PNG exports require Source2Viewer-CLI.exe; set SOURCE2VIEWER_CLI if needed.
The installed game texture version must match the archived manifest; mismatch stops.
Chrome is launched hidden. HTTP/HTTPS are blocked; game events are memory-only.
Temporary files and browser profiles stay in the D: task output directory.

Five complete screenshots, 2x device-density dialog clips, a 720p check and gallery:
  docs/design/difficulty_native_20261019/
Validation and frozen assembly/source hashes:
  output/ui_native_finish_20261019/difficulty_capture_report.json

01 Reborn is the default production material. 02-05 only change preview materials.
The sample has team cap N6 and one pending N4 click, with complete profiles pending.
Locked row labels retain exact full server conditions in native text tooltips.
These captures verify component layout and local state, not native in-game rendering.
