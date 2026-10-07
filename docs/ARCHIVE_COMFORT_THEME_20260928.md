# Archive low-luminance theme — 2026-09-28

User authorized direct archive recoloring. Added archive_comfort.css as the last stylesheet in archive.xml, scoped to ArchiveWindow and ArchiveTooltip.

- Main surface: #1d3035 to #18292e, replacing the large white content Image layer.
- Cards: #2a3e41 to #22353a with a restrained #485b57 border.
- Body text: #cdd0c5; secondary text: #a6b2ad; headings: #d3c299.
- Filter buttons and navigation selection use opaque dark fills, no white sprite backgrounds.
- Header/sidebar decorative artwork dimmed independently of text. Hover uses a subtle border/fill change instead of overall brightness or glowing card corners.
- Card count/unlock status, upgrade/work text, scrollbars, tooltip and art-trial surfaces use the same palette.
- Item icons, archive data, unlock/purchase actions, other windows and lottery remain unchanged.

Source 2 compilation: 3 compiled, 0 failed. Source mirrored into content/dota_addons/survival; runtime VCSS/XML updated. Live screenshot unavailable because local game console 127.0.0.1:29000 refused the connection. No game launch or forced restart performed.

Final readability revision: active archive render and tooltip now apply a shared foreground palette after controls exist, overriding inline colors/backgrounds from old ivory button skins. Names #dce5e8, counts/levels #b5cbd3, selection #cdbb96, body #cdd8dc, titles #d7e1e4, disabled promotion #adbec8 over #24363d. Label weight is normal, no shadow/glow; Arial uses the game CJK fallback. All ArchiveWindow labels and ArchiveTooltip labels participate. Palette tests verify enabled/disabled buttons and stale inline style replacement. No changes to item art or archive interaction.
