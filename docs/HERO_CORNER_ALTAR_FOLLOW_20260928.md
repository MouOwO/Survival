# Hero corner altar icon and camera follow — 2026-09-28

The corner portrait is now a Button containing an Image. All six playable heroes reuse exactly the textures configured on ability_summon_* in npc_abilities_custom.txt. The displayed hero comes from the local successful summon identity, independent of the currently selected unit.

The button routes through the existing owned-hero selection guards using SelectAndFollow. It selects the local hero, centers the camera and starts a 30 ms camera-position loop after the native selection frame. Selecting another unit, Escape/arrow/Space, middle-button panning, hero death, modal/unavailable state or HUD-generation change stops the loop. F1 retains its existing one-time selection/focus behavior.

Validation:
- test_portrait_all_units.cjs: six altar textures match ability KV; identity replacement, hidden/unavailable state, clickable route, unrelated selection isolation.
- test_minimap_shortcut_input.cjs: selected hero and repeated camera updates; delayed native selection start; stop on selection/Escape/death/reload; existing shortcuts unchanged.
- test_box_selection_filter.cjs: 14 scenarios passed.
- Source 2 compilation: 13 compiled, zero failed.
- Live screenshot output/hero_corner_altar_verified.png shows Doom's altar portrait in the corner.
- Live Button Activated event selects hero entity 980 and emits camera_result=move_to_entity. Continuous following was covered by regression tests, not a moving-hero visual test.
- The current match was not restarted. Only the current local hero selection/camera was changed for the click test.


## Superseded: single camera jump

User clarified that clicking the corner portrait must select the hero and jump to its current location once. Removed the follow timer and follow-cancel input handlers. The portrait now calls Select; the old SelectAndFollow entry is retained only as a single-jump alias for cached callbacks during HUD reload. Versioned the button binding so existing buttons are rebound. No selection change or Escape is needed to regain camera control.

Validation: shortcut input and portrait tests passed, including no scheduled follow timer, one camera jump, cached callback and dead-hero behavior. Box selection passed all 19 scenarios.
