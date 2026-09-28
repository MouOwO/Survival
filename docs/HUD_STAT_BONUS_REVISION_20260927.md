# HUD stat revision — 2026-09-27

- Archive: recommendation only, no archive assets/data changed. Suggested dark blue-green content (#172c32), slightly lighter cards (#22383d), warm light text (#d9d2c0), muted gold borders, localized hover emphasis; remove broad white fills/glow.
- Building title moved inside the header (y24..60 before abilities y61). Name and current level share one centered label. Standalone left LV remains collapsed.
- All six custom stat icons removed from hero/monster rows. Names and numeric values remain. Heroes receive a green fixed-bonus row for attack, armor, attack speed and attributes.
- Percentages now expose the actual percentage sources (including multiplicative fixed talents), not flat bonus / original configured base. The old screenshot ratio 60.7 / 72 explains approximately 84.3%; the exact old match source amounts were not retrievable from the console. Tower bonus hover exposes technology/challenge, permanent rewards and fixed talent buckets.
- New combat/hero_display_bonus.lua computes presentation fields only. Fixed equipment, research, permanent rewards and progression rewards are included. Technology accumulated attack, permanent tick/attack/damage/minute counters, weapon growth, monkey/blademaster accumulated growth and progression attack-triggered attributes are excluded.
- Hero progression tracks display_all_attributes only when explicit fixed rewards are applied. Real attribute totals are unchanged. All other combat calculations unchanged.
- White value = authoritative total minus static green bonus. Thus accumulated growth and its amplification stay in white. Parenthesized percent does not re-convert flat amounts.

Validation:
- test_building_hud.cjs, test_unit_stat_visibility.cjs (including hero bonus transitions), test_handoff_refresh.cjs passed.
- test_hero_display_bonus.lua: real technology growth request and progression attack event passed; fixed bonuses remain unchanged while real totals grow.
- test_building_static_bonus.lua, test_building_stat_display.lua passed; 60.7 flat on 72 base no longer becomes 84.3%.
- Existing lumberjack growth/UI and building upgrade lifecycle regressions passed.
- Source 2 compiler: 1 compiled, 0 failed. Content source synchronized, runtime VJS updated.
- Full new-match visual verification remains pending. Console showed post-game and did not return the requested live bonus audit. Start a new match for fresh Lua state and all display fields; no session restart was forced.
