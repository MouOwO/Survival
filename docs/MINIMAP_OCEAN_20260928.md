# Minimap ocean palette, 2026-09-28

Changed the saturated teal ocean to low-saturation deep slate blue with subtle water ripples. This is an original-Dota-inspired palette, not a claim of restoring an official Valve minimap asset.

## Assets and reproducibility

- Final source: `art/maps/minimap/template_map_ocean.tga` (2048x2048).
- Exact previous native source: `art/maps/minimap/template_map_native.tga`.
- Built-in imagegen reference: `art/maps/minimap/ocean_style_reference.png`.
- Rebuild: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_minimap_ocean.ps1`.
- Installed to the content addon's `materials/overviews/template_map.tga`; active material remains `materials/overviews/template_map.vmat`.
- Overview remains pos_x=-16384, pos_y=16384, scale=32. No minimap geometry, markers, input or shortcut changes.

The initial native-regeneration attempt stopped at the existing source/package timestamp check (VMAP is newer than VPK), before any native regeneration. No map compilation or restart was performed. Native simple-background mode was briefly previewed and restored to its previous value 2.

The generated map altered some land details, so it was not deployed as the map. The builder samples only a verified empty-water strip, masks the border-connected ocean of the original native image, and preserves every other original pixel. Isolated inland pools and colored floor art are protected. Water sampling rejects bright/non-water details.

Validation: 1,919,558 ocean pixels changed; 2,274,746 protected pixels, zero changes. Source 2: 2 compiled, 0 failed. Existing minimap sync/resource dependency check passed. Final in-game screenshot `output/minimap_ocean_live_0928.jpg` confirms the dark blue ocean is live; no restart required. New map layouts must be natively regenerated first and the preserved source refreshed before rebuilding this palette.

## Final generation prompt (built-in image_gen; no CLI)

Edit the provided minimap imagery into a deployable square minimap texture. The full square top-down map image without any HUD frame is the geometry source; the user screenshot and other in-game crop are context only. Produce only the square map, no interface border, icons, F2 button, counters, text or extra UI. Preserve the EXACT top-down framing, locations, relative size, shapes, edges, and details of EVERY island, rectangle room, brown/snow/grass area, shoreline and tiny object in that square source. Do not move, redesign, simplify, add, or remove any land or rooms. ONLY change the saturated green/teal ocean/background into original-Dota-style subtle deep slate blue-gray water (#142c39 to #234654), with extremely restrained natural ripples, soft broad depth variations, and a gentle muted lighter blue right at existing shores. Water must recede behind the land. No bright cyan, white foam stripes, glow, added islands, labels, HUD or perspective. Preserve all existing land unchanged. 2048x2048 full square map output.
