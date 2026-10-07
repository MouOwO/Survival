# HUD title, bonus hover, and minimap — 2026-09-28

Implemented:
- Tower stage names (e.g. 1-1) no longer receive a redundant LV suffix. Other building names keep their current level.
- Building title is a separate viewport layer above the panel. The original negative offset inside HandoffBottom was still clipped in a live screenshot, so this layer is independent of that parent. Buff rows and world-label occlusion bounds account for the raised title.
- Numeric fixed bonus and percentage are separate green (#8fe080) and red (#f08078) Labels. No parentheses. Shared across tower, wall health/armor and all six hero rows.
- Root cause of missing hover: HandoffBottom.hittestchildren=false and HandoffCenter.hittestchildren=false blocked the already-bound Label. Both ancestor paths now allow children; only bonus Labels accept input. Skill/inventory/portrait decoration remains input-transparent.
- Hover on either number shows the same source information. Explanation states percentage effect is included in the green bonus total, not an additional bonus to add again.
- Wall source metadata added without modifying gameplay arithmetic. Existing matches lacking this new metadata show an explicit refresh notice rather than fabricated zero sources.
- Native minimap remains interactive. Hide HUDSkinMinimap, GlyphScanContainer and the native Roshan/Tormentor timer decorations. Replace heavy backing with a compact dark blue-green fill and thin muted border.
- User clarified: keep Space builder-selection and F2 return-home buttons. Both and their key bindings unchanged.

Validation:
- Source 2 compilation: 1 compiled, 0 failed; source mirrored to content and VJS updated.
- Building HUD, unit stat visibility, HUD refresh, bonus hit-path/minimap, minimap shortcuts, shortcut input and Lua building bonus regressions passed.
- Current game hot-loaded revised HUD. Live inspected parent hit paths all enabled and GlyphScanContainer collapsed. Screenshots verified complete raised wall title, separate colors, no native side strip and retained Space/F2 buttons.
- Direct mouse hover screenshot was inconclusive while live selection changed to another building; no claim of captured tooltip. Tooltip event dispatch, text and ancestor input path tested. New wall detail fields require a new match.
- Diagnostic screenshots in output/hud_bonus_hover_0928.jpg and output/hud_bonus_0928_small.jpg.

## Typography follow-up

- All shared building titles now use #091f29, sampled from the actual center panel texture, with no black text shadow.
- Building attack/defense label and value: 27 -> 36 design px; wall health bar value: 30 -> 36; green bonus: 25 -> 32; red percentage: 25 -> 30.
- Hero/shared unit captions: 22 -> 26; primary stat values: 30 -> 36; bonus/percentage: 23 -> 26. Three rows redistribute across 96px instead of 82px, ending inside the existing HUD height.
- Building summary rows get 44px height and wall rows move up 5px to stay inside the lower border.
- Existing building HUD, unit visibility, bonus hit-path/minimap checks passed. Source 2: 1 compiled, 0 failed.
