# HUD readability follow-up (2026-09-28)

- Stat captions: 30 design px; primary numbers: 30 px; green/red detail numbers: 24 px. Caption/value boxes adjusted within existing row bounds.
- Shared building title: warm gray #ded5be with subtle dark shadow, replacing terrain-dependent #091f29.
- Tower upgrade tooltips now expose display_current_level/display_target_level from the route row. Internal current_level/target_level remain cumulative for existing consumers and upgrade costs. Visible target field and tooltip header use the same stage levels as tower names.
- Archive comfort theme now hides the actual child nine-slice frames (normal/selected cards, selected navigation, normal/selected filters). Previous parent background overrides left these white images visible.
- Filter text 18 px, item names/unlock badges 16 px; unlocked badge pale green on dark green, locked badge pale gray on dark blue-green. Selected navigation icon no longer black.
- HUD root receives HandoffReadableStats marker so the changed layout triggers live script reload.

Validation:
- 280 routed upgrade previews across all seven classes, plus base towers: passed.
- Existing building HUD, unit stat visibility, tooltip recovery, HUD refresh, bonus hover/minimap checks: passed.
- Source 2 compilation for HUD, tooltip, archive CSS and parent layout: no failures.
- Live archive capture output/archive_cards_verified_0928.jpg confirms dark cards, readable status/filter text and no white navigation frame.
- Live tower runtime: internal 16 -> 17, display 1 -> 2, target name includes LV2. Builder function updated in place in the tools match; no gameplay state reset.
- HUD generation 4 observed after layout refresh. Final screenshot selected a tree, so no claim of a final wall/hero visual comparison.
- No commit or push performed.

## Shared mobile-unit typography follow-up

User reported oversized lumberjack values. All six shared hero/worker/monster stat values now use 26 px normal weight, while captions stay 30 px and bonus text stays 24 px. This keeps one rule for all non-building unit stat columns. Health/mana text, building summaries and the resource-tree panel are unchanged. The root layout marker triggers reloading the current shared HUD.

## Natural caption height correction

Follow-up screenshot still showed small captions and dominant white values. Shared captions previously combined a fixed 34 px box with text-overflow: shrink, which could reduce the requested CJK font size. Captions now use 32 px medium, natural line height, and clip instead of automatic shrinking; white values use 22 px normal with natural height. Each 96 px row reserves 44 px for its caption, 26 px for its value and 26 px for bonus details. This applies to all six mobile-unit stat rows. Added HandoffNaturalStatCaptions layout marker and synchronized content sources.

JavaScript syntax, HUD refresh and unit visibility regressions passed. Resource compiler: 13 compiled, 0 failed. Console connection was refused; no live rendering confirmation is claimed.

## Building title contrast correction

The reported wall title screenshot still showed dark text against grass, inconsistent with the preceding warm-gray source setting. This follow-up uses warm ivory #fff0ce, black text shadow, and a content-width translucent dark-blue background #081d27dd. Shared titles now use bold sans-serif 34 px and natural label height; title bounds sit 50 design px above the HUD with 48 px height, clearing the gold UI edge. The shared presentation refresh reapplies foreground/background contrast. Applies to walls, towers, other buildings, and the resource-tree title. HandoffReadableBuildingTitle marks the layout refresh.

Building and tree HUD regression checks passed; resource compiler: 13 compiled, 0 failed. Local console refused connection; live screenshot consistency remains unverified.

## Compact utility-building panels

Farm, research, main-city and other utility buildings now use 205 design px height instead of 330, retaining the 116 px ability icons, at least 800 px width and 28 px below the icon row. Geometry accepts the actual presentation classification; walls and towers retain 330 px for their combat rows, and the tree retains its own 185 px layout. All building panels anchor six screen-layout px above the bottom. Height participates in the HUD reflow signature, and the existing production queue follows the resulting geometry.

Building geometry across three viewport sizes and one/two/four/ten abilities, production queue and HUD refresh tests passed. Compilation: 13 compiled, 0 failed. Console reconnected and screenshots were captured; the live session still showed the old taller research panel, so the new utility layout was not visually verified in this session. No match restart was issued. Re-enter the test map to load the new layout/scripts.

## Balanced primary values

After user screenshot feedback, shared primary white values increase from 22 to 28 design px, with captions remaining 32 px and bonus values 24 px. Rows use 98 px spacing starting at y=32; primary values begin at +42 and bonuses at +74, keeping all three rows inside the 330 px HUD. Applies to heroes, workers and monsters. Syntax/visibility checks passed; compilation: 13 compiled, zero failed. This revision has not been visually verified in game.
