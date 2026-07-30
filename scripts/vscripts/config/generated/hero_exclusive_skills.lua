-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_exclusive_skills.csv
local M = {}
M.rows = {
    { exclusive_entry_id = "exclusive_axe_01", exclusive_group_id = "exclusive_axe", hero_id = "hero_axe", skill_id = "skill_axe_exclusive", initial_level = 1, guaranteed = true, enabled = true },
    { exclusive_entry_id = "exclusive_slark_01", exclusive_group_id = "exclusive_slark", hero_id = "hero_slark", skill_id = "skill_slark_exclusive", initial_level = 1, guaranteed = true, enabled = true },
    { exclusive_entry_id = "exclusive_jugg_01", exclusive_group_id = "exclusive_juggernaut", hero_id = "hero_juggernaut", skill_id = "skill_juggernaut_exclusive", initial_level = 1, guaranteed = true, enabled = true },
    { exclusive_entry_id = "exclusive_monkey_01", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_exclusive", initial_level = 1, guaranteed = true, enabled = true },
    { exclusive_entry_id = "exclusive_monkey_02", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_fury", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_monkey_03", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_swiftness", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_monkey_04", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_agility", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_blademaster_01", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_exclusive", initial_level = 1, guaranteed = true, enabled = true },
    { exclusive_entry_id = "exclusive_blademaster_02", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_agility", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_blademaster_03", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_swiftness", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_blademaster_04", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_mobility", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["exclusive_entry_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M

