# Resource tree HUD (2026-09-28)

- Identify enemy_tree / npc_dota_unit_enemy_tree or is_resource_tree metadata separately from buildings, heroes and monsters. No ownership/team changes.
- Keep name and current/max level in the raised title, live health and full current defense. Defense remains useful because lumberjack research can reduce it.
- Remove portrait, level medallion, attack/speed/attributes, mana, inventory, ability area and all player bonus labels.
- Compact geometry: 680x185 design units, compared with 330-unit regular panel height. Title and health/defense rows fit the shorter panel.
- Restore portrait, inventory, mana and ability area when selection returns to a hero or another unit. Existing wall/tower rules remain intact.
- Tests: building HUD + new resource tree assertions, unit classification/visibility + new tree assertions, HUD refresh all pass. Covers stale player bonus fields, live defense changes, multiselect and three viewport sizes.
- Source 2 parent-layout compilation: 13 compiled, 0 failed. Source mirrored into content.
- Live console refused connection (127.0.0.1:29000); no claim of in-game visual validation for this change. No match restart/termination attempted.

## Red resource-tree health bar

The tree HUD health fill now uses a red gradient (#e4473d to #a21e1c) to match its enemy health-bar presentation. Health numbers retain their light color. The fill is a Panel with the same percentage clip; non-tree selection restores the original green health texture. Building/tree layout and selection restoration tests passed. Compilation: 13 compiled, zero failed; no visual confirmation of this revision yet.
