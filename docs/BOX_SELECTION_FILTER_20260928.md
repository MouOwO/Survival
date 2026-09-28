# Box selection filtering (2026-09-28)

## Behavior

- After a left-button rectangle drag, exclude fixed buildings, tower/wall model proxies, ultimate towers and resource trees from the newly selected group.
- Keep heroes, builders, lumberjacks and other normal mobile selections in their original native order.
- Single click, small cursor jitter, double click, keyboard control groups and right click stay native.
- If the rectangle contains only excluded targets, restore the pre-drag selection; if there was no selection, use the valid builder/real hero fallback.
- Shift preserves previously selected buildings intentionally selected by the player, but does not add newly boxed buildings.

## Implementation

`box_selection_filter.js` observes the shared input dispatcher without installing another mouse callback. The dispatcher captures click behavior before placement handlers change it and reports whether they consumed the input. The filter only arms for unconsumed left presses in normal selection mode, outside HUD occlusion and modal windows. A drag must span at least eight screen pixels.

Native rectangle selection still performs entity picking. Correction is bounded to 200 ms after release and stops after one successful rewrite. New mouse presses/ordinary keys cancel pending correction; stale HUD generations cannot change the current selection. There is no permanent selection watcher that would prevent clicking buildings.

Reference checked: https://raw.githubusercontent.com/ModDota/TypeScriptDeclarations/master/packages/panorama-types/types/api.d.ts (mouse callback, click behaviors, SelectUnit API declarations).

## Validation

- `tools/test_box_selection_filter.cjs`: 14 scenarios pass, exercising the actual controller and the shared mouse callback wiring.
- `tools/test_minimap_shortcut_input.cjs`: existing shared keyboard/button, F1/F2/Space, focus/modal and lifecycle tests pass.
- Source mirrored into content; parent HUD compiled: 13 compiled, 0 failed.
- Live console unavailable (127.0.0.1:29000 refused), so actual drag behavior has not yet been checked in-game. No game restart/termination performed.

## Live failure diagnosis and mouse-state fix (2026-09-28)

The user reproduced buildings remaining in a drag selection. Live diagnostics established:
- The separately included filter was not active in the running HUD. Integration into the existing ui_bootstrap.js input initialization produced a registered, active filter (generation 20).
- Actual mouse traces contained pressed events only, no released events. The pending gesture therefore never reached the old release-only filtering path. Building classification itself correctly identified building_research_lab and the other building names.
- The engine's own cl_panorama_script_help_2 confirms GameUI.IsMouseDown(integer).

The filter now polls IsMouseDown(0) every 16 ms only while a normal world left-button gesture exists. Release detection classifies the movement threshold and opens a bounded 650 ms reconciliation window; late native selection updates cannot re-add buildings after the first rewrite. New clicks/control-group keys cancel the window. Identical fallback selections are not rewritten. Single clicks, ability targeting, placement input, UI/modal clicks and Shift-preserved intentional selections retain their prior behavior. The standalone filter and temporary probe modules were removed; tools/test_box_selection_filter.cjs runs the integrated source directly.

Validation: 19 filter scenarios passed, including press-only native input, delayed native overwrites, and identical building fallback. Existing shortcut/follow and lumberjack queue tests passed. Final compiler output: 13 compiled, 0 failed. Live generation 22 reported active=true and IsMouseDown=false after final deployment. The user was viewing the archive, so no automated mouse gesture was injected into that interface; a real mixed drag after the final fix remains pending user confirmation. No match restart was issued.
