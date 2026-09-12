package.path = "scripts/vscripts/?.lua;" .. package.path
local rewards = require("systems/archive_challenge_rewards")
local fragments = require("config/generated/archive_fragment_definitions")
local levels = require("config/generated/archive_fragment_levels")
local definitions = require("config/generated/archive_challenge_definitions")
local shadow_rules = require("config/generated/archive_shadow_challenge_drop_rules")
local shadow_items = require("config/generated/archive_shadow_items")
local schema = require("config/generated/player_gameplay_stats")
assert(#fragments.rows == 12)
local active = 0
for _, row in ipairs(definitions.rows) do
    if row.enabled then active = active + 1 end
end
assert(active == 22)
for _, row in ipairs(levels.rows) do
    for _, field in ipairs(row.effect_ids) do assert(schema.by_id[field], field) end
end
RandomInt = function(a) return a end
local function effect(stats, row)
    for i, field in ipairs(row.effect_ids) do stats[field] = (stats[field] or 0) + tonumber(row.effect_values[i]) end
end
local save, stats = {}, {}
local function kill(challenge, day, pass)
    local command = {challenge_id=challenge,day_key=day}
    assert(rewards.apply(command,save,stats,pass,effect))
    return command
end
for i = 1, 20 do kill("hunt_01", "day1", false) end
assert(save.fragment_counts.fragment_01 == 20)
assert(save.fragment_levels.fragment_01 == 1 and stats.hero_health_bonus_pct == 3)
kill("hunt_01", "day1", false)
assert(save.fragment_totals.fragment_01 == 20, "daily cap")
for i = 1, 20 do kill("hunt_01", "day1", true) end
assert(save.fragment_totals.fragment_01 == 40 and stats.hero_armor_bonus_pct == 3)
kill("hunt_01", "day1", true)
assert(save.fragment_totals.fragment_01 == 40)
for day = 2, 9 do for i = 1, 20 do kill("hunt_01", "day"..day, false) end end
assert(save.fragment_totals.fragment_01 == 200)
assert(save.fragment_levels.fragment_01 == 10)
assert(stats.hero_health_bonus_pct == 3 and stats.hero_damage_attack_growth == 1)
assert(not rewards.promote({fragment_id="fragment_01"},save,stats,effect), "strictly above 200")
kill("hunt_01", "day10", false)
assert(rewards.promote({fragment_id="fragment_01"},save,stats,effect))
assert(save.fragment_counts.fragment_01 == 191 and save.fragment_totals.fragment_01 == 201)
assert(save.fragment_levels.fragment_01 == 10 and save.fragment_counts.fragment_05 == 1)
assert(save.fragment_totals.fragment_05 == 1)
assert(not rewards.promote({fragment_id="fragment_12"},save,stats,effect))
save.fragment_counts.fragment_05 = 999
local before = save.fragment_counts.fragment_01
assert(not rewards.promote({fragment_id="fragment_01"},save,stats,effect))
assert(save.fragment_counts.fragment_01 == before)
save, stats = {}, {}
for index = 1, 3 do
    local rule = assert(shadow_rules.by_id["shadow_" .. index])
    assert(rule.source_boss_difficulty == "n" .. index
        and rule.drop_count == 2 and rule.pass_extra_count == 0
        and rule.allow_duplicates == true)
end
for _, item in ipairs(shadow_items.rows) do
    assert(item.source_boss_difficulty:match("^n[1-4]$"))
end
local first_drop = kill("shadow_1", "day1", false)
assert(#first_drop.drops == 2 and first_drop.drops[1] == "shadow_01"
    and first_drop.drops[2] == "shadow_01", "two independent rolls may duplicate")
assert(save.shadow_counts.shadow_01 == 2 and stats.initial_wood == 20)
local second_drop = kill("shadow_2", "day1", true)
assert(#second_drop.drops == 2, "shadow 1-3 pass must still finish at two items")
assert(save.shadow_counts.shadow_06 == 2 and stats.hero_initial_attributes == 60)
kill("shadow_3", "day1", false)
assert(save.shadow_counts.shadow_12 == 2)
kill("shadow_4", "day1", false)
assert(save.shadow_counts.shadow_18 == 2)
for i = 1, 30 do kill("cage_1", "day1", false) end
assert(save.cage_counts.cage_01 == 30)
kill("cage_2", "day1", false)
assert(save.cage_counts.cage_10 == nil, "cage global daily cap")
for i = 1, 30 do kill("cage_2", "day1", true) end
assert(save.cage_counts.cage_10 == 60 and save.daily.day1.cage_total == 90)
kill("cage_3", "day1", true)
assert(save.cage_counts.cage_19 == nil)
kill("cage_3", "day2", true)
assert(save.cage_counts.cage_19 == 2)
assert(#rewards.fragment_rows({}, save) == 12)
for i = 5, 12 do
    kill(string.format("hunt_%02d", i), "expanded", false)
    assert((save.fragment_counts[string.format("fragment_%02d", i)] or 0) > 0)
end
for i = 4, 6 do
    local drops = kill("cage_" .. i, "expanded", false).drops
    assert(#drops == 1 and drops[1] == string.format("cage_%02d", (i-1)*9+1))
end
local cage_items = require("config/generated/archive_cage_items")
assert(#cage_items.rows == 54)
for _, row in ipairs(cage_items.rows) do
    for _, field in ipairs(row.effect_ids) do assert(schema.by_id[field], field) end
end
print("ARCHIVE_CHALLENGE_REWARDS_PASS: per-boss pools, daily limits, pass, levels, exchange, caps")
